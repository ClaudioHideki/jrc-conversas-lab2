require 'rails_helper'

RSpec.describe 'Call Center last configured eligible agent withdrawal', type: :request do
  include ActiveSupport::Testing::TimeHelpers
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:operator) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:operator_member) { account.account_users.find_by!(user: operator) }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, name: 'SYNTHETIC active unit', code: 'A', kind: 'sac') }
  let(:queue) { JrcContactCenter::Queue.create!(account: account, unit: unit, name: 'SYNTHETIC active queue', code: 'A') }
  let(:membership) { JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: operator_member) }
  let(:headers) { actor.create_new_auth_token }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/queue_memberships/#{membership.id}" }
  let(:payload) { { queue_membership: { active: false }, expected_revision: JrcContactCenter::ConfigurationRevision.token(membership) } }
  let(:audits) { Audited.audit_class.where(auditable: membership, action: 'update') }

  after { Current.reset }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
    role = create(:custom_role, account: account, permissions: JrcContactCenter::ModulePolicy::PERMISSIONS)
    member.update!(custom_role: role)
  end

  it 'shows the actual impact and blocks the first withdrawal without changing data or audit' do
    patch endpoint, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.parsed_body.fetch('review')).to include('account_id' => account.id.to_s, 'queue_id' => queue.id.to_s,
                                                          'previous_count' => 1, 'remaining_count' => 0)
    expect(membership.reload.active).to be(true)
    expect(audits).to be_empty
  end

  it 'accepts an explicitly confirmed signed review and records it in the same native audit' do
    patch endpoint, headers: headers, params: payload, as: :json
    receipt = response.parsed_body.fetch('review').fetch('review_token')
    confirmed = payload.merge(manager_confirmation: { confirmed: true, review_token: receipt })
    patch endpoint, headers: headers, params: confirmed, as: :json
    expect(response).to have_http_status(:ok)
    expect(membership.reload.active).to be(false)
    review = audits.sole.audited_changes.fetch('manager_review')
    expect(review).to include('account_user_id' => member.id.to_s, 'queue_id' => queue.id.to_s, 'previous_count' => 1, 'remaining_count' => 0)
    expect(review.fetch('receipt_sha256')).to eq(Digest::SHA256.hexdigest(receipt))
    expect(audits.sole.audited_changes.to_json).not_to include(receipt)
  end

  [false, 'true', nil].each do |confirmation|
    it "does not mistake #{confirmation.inspect} for explicit manager confirmation" do
      patch endpoint, headers: headers, params: payload, as: :json
      receipt = response.parsed_body.fetch('review').fetch('review_token')
      rejected = payload.merge(manager_confirmation: { confirmed: confirmation, review_token: receipt })
      patch endpoint, headers: headers, params: rejected, as: :json
      expect(response).to have_http_status(:conflict)
      expect(membership.reload.active).to be(true)
      expect(audits).to be_empty
    end
  end

  it 'rejects a forged or malformed receipt instead of trusting a browser impact count' do
    forged = payload.merge(manager_confirmation: { confirmed: true, review_token: 'forged', remaining_count: 1 })
    patch endpoint, headers: headers, params: forged, as: :json
    expect(response).to have_http_status(:conflict)
    patch endpoint, headers: headers, params: payload.merge(manager_confirmation: 'not-an-object'), as: :json
    expect(response).to have_http_status(:conflict)
    expect(membership.reload.active).to be(true)
  end

  it 'invalidates the receipt when the proposed draft changes' do
    previous_priority = membership.priority
    patch endpoint, headers: headers, params: payload, as: :json
    receipt = response.parsed_body.fetch('review').fetch('review_token')
    changed = payload.deep_merge(queue_membership: { priority: 2 }).merge(manager_confirmation: { confirmed: true, review_token: receipt })
    patch endpoint, headers: headers, params: changed, as: :json
    expect(response).to have_http_status(:conflict)
    expect(membership.reload).to have_attributes(active: true, priority: previous_priority)
    expect(audits).to be_empty
  end

  it 'does not let another authorized manager reuse a review issued to the first one' do
    patch endpoint, headers: headers, params: payload, as: :json
    receipt = response.parsed_body.fetch('review').fetch('review_token')
    other = create(:user, :contact_center_eligible, account: account, role: :administrator)
    confirmed = payload.merge(manager_confirmation: { confirmed: true, review_token: receipt })
    patch endpoint, headers: other.create_new_auth_token, params: confirmed, as: :json
    expect(response).to have_http_status(:conflict)
    expect(membership.reload.active).to be(true)
  end

  it 'revalidates current manager eligibility despite a previously valid receipt' do
    patch endpoint, headers: headers, params: payload, as: :json
    receipt = response.parsed_body.fetch('review').fetch('review_token')
    JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member).update!(eligible: false)
    confirmed = payload.merge(manager_confirmation: { confirmed: true, review_token: receipt })
    patch endpoint, headers: headers, params: confirmed, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(membership.reload.active).to be(true)
  end

  it 'does not treat provider_pending or offline status as absence of configured eligibility' do
    expect(JrcContactCenter::AgentStateSnapshot.new(account_user: operator_member).call.fetch(:eligible)).to be(false)
    patch endpoint, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:conflict)
    expect(membership.reload.active).to be(true)
  end

  it 'allows ordinary deactivation when another agent is currently configured and eligible' do
    other = create(:user, :contact_center_eligible, account: account, role: :agent)
    JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: account.account_users.find_by!(user: other))
    patch endpoint, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:ok)
    expect(membership.reload.active).to be(false)
    expect(audits.sole.audited_changes).not_to have_key('manager_review')
  end

  it 'does not count a supervisor-only membership as an agent replacement' do
    other = create(:user, :contact_center_eligible, account: account, role: :agent)
    peer = account.account_users.find_by!(user: other)
    JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: peer, role: 'supervisor')
    patch endpoint, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:conflict)
    expect(membership.reload.active).to be(true)
  end

  it 'does not count a second membership whose explicit eligibility was withdrawn' do
    other = create(:user, :contact_center_eligible, account: account, role: :agent)
    peer = account.account_users.find_by!(user: other)
    JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: peer)
    JrcContactCenter::AccessGrant.find_by!(account: account, account_user: peer).update!(eligible: false)
    patch endpoint, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:conflict)
    expect(membership.reload.active).to be(true)
  end

  it 'does not block maintenance of a queue that is already inactive' do
    queue.update!(status: 'inactive')
    patch endpoint, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:ok)
    expect(membership.reload.active).to be(false)
  end

  it 'recognizes a valid same-queue replacement rather than reporting a false empty queue' do
    other = create(:user, :contact_center_eligible, account: account, role: :agent)
    replacement = account.account_users.find_by!(user: other)
    patch endpoint, headers: headers, params: payload.deep_merge(queue_membership: { account_user_id: replacement.id, active: true }), as: :json
    expect(response).to have_http_status(:ok)
    expect(membership.reload).to have_attributes(account_user_id: replacement.id, active: true)
  end

  it 'does not disclose review details across Accounts' do
    other = create(:account)
    foreign = create(:user, :contact_center_eligible, account: other, role: :administrator)
    patch endpoint, headers: foreign.create_new_auth_token, params: payload, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(queue.name)
    expect(membership.reload.active).to be(true)
  end

  it 'rejects an expired impact review even if the persisted membership has not changed' do
    patch endpoint, headers: headers, params: payload, as: :json
    receipt = response.parsed_body.fetch('review').fetch('review_token')
    confirmed = payload.merge(manager_confirmation: { confirmed: true, review_token: receipt })
    travel 11.minutes do
      patch endpoint, headers: headers, params: confirmed, as: :json
      expect(response).to have_http_status(:conflict)
    end
    expect(membership.reload.active).to be(true)
    expect(audits).to be_empty
  end

  it 'does not let a signed review retain access after the manager moves to another business unit' do
    company = account.master_companies.create!(name: 'SYNTHETIC review issuer', relationship_type: 'internal')
    business = %w[A B].map do |code|
      JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: "SYNTHETIC review #{code}", code: code)
    end
    unit.update!(settings: { issuer_company_id: company.id, business_unit_id: business.first.id })
    [actor, operator].each do |person|
      JrcCrm::UserBusinessUnit.create!(account: account, user: person, scope: 'BUSINESS_UNIT', company: company,
                                       business_unit: business.first, active: true, structure_managed: true)
    end
    patch endpoint, headers: headers, params: payload, as: :json
    receipt = response.parsed_body.fetch('review').fetch('review_token')
    JrcCrm::UserBusinessUnit.find_by!(account: account, user: actor).update!(business_unit: business.last)
    confirmed = payload.merge(manager_confirmation: { confirmed: true, review_token: receipt })
    patch endpoint, headers: headers, params: confirmed, as: :json
    expect(response).to have_http_status(:not_found)
    expect(membership.reload.active).to be(true)
    expect(audits).to be_empty
  end

  it 'filters the signed review receipt with the native request-log parameter filters' do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    result = filter.filter('manager_confirmation' => { 'review_token' => 'SYNTHETIC sensitive review receipt', 'confirmed' => true })
    expect(result.dig('manager_confirmation', 'review_token')).to eq('[FILTERED]')
    expect(result.to_json).not_to include('SYNTHETIC sensitive review receipt')
  end

  it 'does not carry a consumed manager review into later ordinary updates on the same record object' do
    patch endpoint, headers: headers, params: payload, as: :json
    token = response.parsed_body.fetch('review').fetch('review_token')
    context = { account: account, account_user: member, user: actor }
    review = JrcContactCenter::QueueWithdrawalReview.new(account: account, member: member,
                                                        confirmation: { confirmed: true, review_token: token })
    writer = JrcContactCenter::ConfigurationWrite.new(account: account, access: JrcContactCenter::AccessScope.new(user_context: context))
    Current.user = actor
    row = writer.update!(JrcContactCenter::QueueMembership.where(account: account), membership.id,
                         expected_revision: payload.fetch(:expected_revision), review: review) { { active: false } }
    expect(row.cc_withdrawal_review).to be_nil
    expect(audits.sole.audited_changes).to have_key('manager_review')
    row.update!(priority: row.priority + 1)
    expect(audits.count).to eq(2)
    expect(audits.order(:id).last.audited_changes).not_to have_key('manager_review')
  end
end

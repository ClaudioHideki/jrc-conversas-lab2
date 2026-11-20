require 'rails_helper'

RSpec.describe 'Manager review of Call Center team-source last-agent loss', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let!(:headers) { actor.create_new_auth_token }
  let(:manager) { account.account_users.find_by!(user: actor) }
  let(:recipient) { create(:user, :contact_center_eligible, account: account) }
  let(:member) { account.account_users.find_by!(user: recipient) }
  let(:team) { create(:team, account: account) }
  let(:grant) { JrcContactCenter::AccessGrant.find_by!(account: account, team: team) }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, code: 'SYNTHETIC', name: 'SYNTHETIC local unit', kind: 'sac') }
  let(:queue) { JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'SYNTHETIC', name: 'SYNTHETIC last queue') }
  let!(:membership) { JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/access_authorizations/teams/#{team.id}" }
  let(:authority) { JrcContactCenter::AccessAuthorization.new(context: { account: account, account_user: manager, user: actor }) }
  let(:payload) { { authorization: { active: false }, expected_revision: authority.revision(team, grant) } }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
    manager.update!(custom_role: create(:custom_role, account: account, permissions: JrcContactCenter::ModulePolicy::PERMISSIONS))
    member.update!(custom_role: create(:custom_role, account: account, permissions: []))
    team.add_members([recipient.id])
    JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: %w[jrc_contact_center_view jrc_contact_center_operate])
  end

  it 'requires a fresh explicit manager receipt and makes no status, roster or queue change before confirmation' do
    patch endpoint, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('review', 'operation')).to eq('deactivate_source')
    expect(response.parsed_body.dig('review', 'queues')).to contain_exactly(
      a_hash_including('queue_id' => queue.id.to_s, 'previous_count' => 1, 'remaining_count' => 0)
    )
    expect(JrcContactCenter::TeamState.where(team: team)).to be_empty
    expect(team.members).to include(recipient)
    expect(membership.reload).to be_active
  end

  it 'persists reviewed inactivation and the queue impact audit atomically without withdrawing shared membership' do
    patch endpoint, headers: headers, params: payload, as: :json
    token = response.parsed_body.fetch('review').fetch('review_token')
    patch endpoint, headers: headers, params: payload.merge(manager_confirmation: { confirmed: true, review_token: token }), as: :json
    expect(response).to have_http_status(:ok)
    expect(JrcContactCenter::TeamState.find_by!(team: team)).not_to be_active
    expect(team.members).to include(recipient)
    expect(membership.reload).to be_active
    review = Audited.audit_class.where(auditable: queue, comment: JrcContactCenter::ConfigurationAudit::COMMENT).last
    expect(review.audited_changes.fetch('manager_review')).to include(
      'kind' => 'jrc_cc_team_source_activity_v1', 'operation' => 'deactivate_source', 'receipt_sha256' => Digest::SHA256.hexdigest(token)
    )
    expect(review.audited_changes.to_json).not_to include(token)
  end

  [false, 'true', nil].each do |confirmed|
    it "rejects #{confirmed.inspect} instead of an explicit confirmation" do
      patch endpoint, headers: headers, params: payload, as: :json
      token = response.parsed_body.fetch('review').fetch('review_token')
      patch endpoint, headers: headers, params: payload.merge(manager_confirmation: { confirmed: confirmed, review_token: token }), as: :json
      expect(response).to have_http_status(:conflict)
      expect(JrcContactCenter::TeamState.where(team: team)).to be_empty
      expect(team.members).to include(recipient)
    end
  end

  it 'does not reuse the source-status receipt as a shared roster withdrawal receipt' do
    patch endpoint, headers: headers, params: payload, as: :json
    token = response.parsed_body.fetch('review').fetch('review_token')
    patch "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members", headers: headers,
            params: { user_ids: [], manager_confirmation: { confirmed: true, review_token: token } }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(team.members).to include(recipient)
    expect(JrcContactCenter::TeamState.where(team: team)).to be_empty
  end

  it 'does not require an empty-queue receipt if another individually eligible operator remains' do
    other = create(:user, :contact_center_eligible, account: account)
    other_member = account.account_users.find_by!(user: other)
    JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: other_member)
    patch endpoint, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:ok)
    expect(JrcContactCenter::TeamState.find_by!(team: team)).not_to be_active
    expect(JrcContactCenter::ConfiguredQueueEligibility.new(account: account).call(membership.reload)).to be(false)
  end
end

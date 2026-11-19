require 'rails_helper'

RSpec.describe 'Native team removal and last configured eligible queue agent', type: :request do
  include ActiveSupport::Testing::TimeHelpers
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:manager) { account.account_users.find_by!(user: actor) }
  let(:operator) { create(:user, :contact_center_eligible, account: account) }
  let(:member) { account.account_users.find_by!(user: operator) }
  let(:team) { create(:team, account: account) }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC roster issuer', relationship_type: 'internal') }
  let(:business) { account.jrc_crm_business_units.create!(operating_company: company, code: 'ROSTER', name: 'SYNTHETIC business') }
  let(:unit) do
    JrcContactCenter::Unit.create!(account: account, code: 'ROSTER', name: 'SYNTHETIC operational unit', kind: 'sac',
                                   settings: { issuer_company_id: company.id, business_unit_id: business.id })
  end
  let(:queue) { JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'ROSTER', name: 'SYNTHETIC last-agent queue') }
  let!(:membership) { JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members" }
  let!(:headers) { actor.create_new_auth_token }
  let(:audits) { Audited.audit_class.where(auditable: queue, action: 'update', comment: JrcContactCenter::ConfigurationAudit::COMMENT) }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'GROUP', structure_managed: true)
    member.update!(custom_role: create(:custom_role, account: account, permissions: []))
    team.add_members([operator.id])
    account.jrc_crm_team_scopes.create!(team: team, scope: 'GROUP')
    account.jrc_crm_user_business_units.create!(user: operator, team: team, scope: 'GROUP', structure_managed: true)
    JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: %w[jrc_contact_center_view jrc_contact_center_operate])
  end

  after { Current.reset }

  %i[patch delete].each do |verb|
    it "blocks unreviewed #{verb} without changing membership, stored grants, queue, audit or cache" do
      original = team.team_members.sole.id
      targets = verb == :patch ? [] : [operator.id]
      allow(Redis::Alfred).to receive(:setex).and_call_original
      expect(Redis::Alfred).not_to receive(:setex).with("idb-cache-key-account-#{account.id}-team", anything, anything)
      public_send(verb, endpoint, headers: headers, params: { user_ids: targets }, as: :json)
      expect(response).to have_http_status(:conflict)
      expect(response.headers['Cache-Control']).to include('no-store')
      expect(response.parsed_body.dig('review', 'queues')).to contain_exactly(
        a_hash_including('queue_id' => queue.id.to_s, 'previous_count' => 1, 'remaining_count' => 0)
      )
      expect(team.team_members.reload.pluck(:id)).to eq([original])
      expect(membership.reload).to be_active
      expect(audits).to be_empty
    end

    it "requires explicit manager confirmation for #{verb} and writes a scoped native queue audit atomically" do
      targets = verb == :patch ? [] : [operator.id]
      public_send(verb, endpoint, headers: headers, params: { user_ids: targets }, as: :json)
      token = response.parsed_body.fetch('review').fetch('review_token')
      payload = { user_ids: targets, manager_confirmation: { confirmed: true, review_token: token } }
      public_send(verb, endpoint, headers: headers, params: payload, as: :json)
      expect(response).to have_http_status(:ok)
      expect(team.team_members.reload).to be_empty
      expect(membership.reload).to be_active
      expect(audits.sole.audited_changes.fetch('manager_review')).to include(
        'kind' => 'jrc_cc_team_roster_withdrawal_v1', 'team_id' => team.id.to_s, 'operation' => verb == :patch ? 'update' : 'destroy',
        'account_user_id' => manager.id.to_s, 'receipt_sha256' => Digest::SHA256.hexdigest(token)
      )
      expect(audits.sole.audited_changes.dig('cc_scope', 'after', 'unit_id')).to eq(unit.id.to_s)
      expect(audits.sole.audited_changes.to_json).not_to include(token)
      expect(account.jrc_crm_user_business_units.find_by!(user: operator)).to be_active
    end
  end

  [false, 'true', nil].each do |confirmed|
    it "does not accept #{confirmed.inspect} as manager confirmation" do
      patch endpoint, headers: headers, params: { user_ids: [] }, as: :json
      token = response.parsed_body.fetch('review').fetch('review_token')
      patch endpoint, headers: headers, params: { user_ids: [], manager_confirmation: { confirmed: confirmed, review_token: token } }, as: :json
      expect(response).to have_http_status(:conflict)
      expect(team.members).to include(operator)
      expect(audits).to be_empty
    end
  end

  it 'does not accept a forged receipt or malformed manager confirmation object' do
    [{ confirmed: true, review_token: 'forged' }, 'not-an-object'].each do |confirmation|
      patch endpoint, headers: headers, params: { user_ids: [], manager_confirmation: confirmation }, as: :json
      expect(response).to have_http_status(:conflict)
    end
    expect(team.members).to include(operator)
    expect(audits).to be_empty
  end

  it 'does not reuse the receipt after the proposed roster changes' do
    patch endpoint, headers: headers, params: { user_ids: [] }, as: :json
    token = response.parsed_body.fetch('review').fetch('review_token')
    another = create(:user, account: account)
    patch endpoint, headers: headers,
                    params: { user_ids: [another.id], manager_confirmation: { confirmed: true, review_token: token } }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(team.members).to include(operator)
    expect(team.members).not_to include(another)
    expect(audits).to be_empty
  end

  it 'does not reuse the receipt after the actual roster changes' do
    patch endpoint, headers: headers, params: { user_ids: [] }, as: :json
    token = response.parsed_body.fetch('review').fetch('review_token')
    another = create(:user, account: account)
    team.add_members([another.id])
    patch endpoint, headers: headers, params: { user_ids: [], manager_confirmation: { confirmed: true, review_token: token } }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(team.members.pluck(:id)).to contain_exactly(operator.id, another.id)
    expect(audits).to be_empty
  end

  it 'binds the receipt to the current manager and native operation' do
    patch endpoint, headers: headers, params: { user_ids: [] }, as: :json
    token = response.parsed_body.fetch('review').fetch('review_token')
    other = create(:user, :contact_center_eligible, account: account, role: :administrator)
    account.jrc_crm_user_business_units.create!(user: other, scope: 'GROUP', structure_managed: true)
    confirmation = { confirmed: true, review_token: token }
    patch endpoint, headers: other.create_new_auth_token, params: { user_ids: [], manager_confirmation: confirmation }, as: :json
    expect(response).to have_http_status(:conflict)
    delete endpoint, headers: headers, params: { user_ids: [operator.id], manager_confirmation: confirmation }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(team.members).to include(operator)
  end

  it 'expires the review without changing the membership or audit' do
    patch endpoint, headers: headers, params: { user_ids: [] }, as: :json
    token = response.parsed_body.fetch('review').fetch('review_token')
    travel 11.minutes do
      patch endpoint, headers: headers, params: { user_ids: [], manager_confirmation: { confirmed: true, review_token: token } }, as: :json
      expect(response).to have_http_status(:conflict)
    end
    expect(team.members).to include(operator)
    expect(audits).to be_empty
  end

  it 'rejects a stale review when a queue revision changes' do
    patch endpoint, headers: headers, params: { user_ids: [] }, as: :json
    token = response.parsed_body.fetch('review').fetch('review_token')
    queue.update!(name: 'SYNTHETIC changed queue')
    audits_before = audits.count
    patch endpoint, headers: headers, params: { user_ids: [], manager_confirmation: { confirmed: true, review_token: token } }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(team.members).to include(operator)
    expect(audits.count).to eq(audits_before)
  end

  it 'also binds the reviewed operation to the current operational unit revision' do
    patch endpoint, headers: headers, params: { user_ids: [] }, as: :json
    token = response.parsed_body.fetch('review').fetch('review_token')
    unit.update!(name: 'SYNTHETIC changed reviewed unit')
    patch endpoint, headers: headers, params: { user_ids: [], manager_confirmation: { confirmed: true, review_token: token } }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(team.members).to include(operator)
    expect(audits).to be_empty
  end

  it 'requires a fresh review after eligible agents change even if both roster sets remain identical' do
    other = create(:user, account: account)
    peer = account.account_users.find_by!(user: other)
    peer.update!(custom_role: member.custom_role)
    grant = JrcContactCenter::AccessGrant.create!(account: account, account_user: peer, eligible: false)
    team.add_members([other.id])
    account.jrc_crm_user_business_units.create!(user: other, team: team, scope: 'GROUP', structure_managed: true)
    JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: peer)
    patch endpoint, headers: headers, params: { user_ids: [] }, as: :json
    token = response.parsed_body.fetch('review').fetch('review_token')
    grant.update!(eligible: true)
    patch endpoint, headers: headers, params: { user_ids: [], manager_confirmation: { confirmed: true, review_token: token } }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('review', 'queues', 0, 'previous_count')).to eq(2)
    expect(team.members.pluck(:id)).to contain_exactly(operator.id, other.id)
    expect(audits).to be_empty
  end

  it 'reauthorizes manager eligibility instead of treating a signed receipt as a grant' do
    patch endpoint, headers: headers, params: { user_ids: [] }, as: :json
    token = response.parsed_body.fetch('review').fetch('review_token')
    JrcContactCenter::AccessGrant.find_by!(account: account, account_user: manager).update!(eligible: false)
    patch endpoint, headers: headers, params: { user_ids: [], manager_confirmation: { confirmed: true, review_token: token } }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(queue.name)
    expect(team.members).to include(operator)
  end

  it 'denies the whole withdrawal before exposing any out-of-scope queue' do
    account.jrc_crm_user_business_units.find_by!(user: actor).update!(active: false)
    patch endpoint, headers: headers, params: { user_ids: [] }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(queue.name)
    expect(team.members).to include(operator)
    expect(audits).to be_empty
  end

  it 'rolls back the native roster if its mandatory queue audit cannot be persisted' do
    patch endpoint, headers: headers, params: { user_ids: [] }, as: :json
    token = response.parsed_body.fetch('review').fetch('review_token')
    allow(JrcContactCenter::ConfigurationAudit).to receive(:write_team_withdrawal!).and_raise(ActiveRecord::RecordInvalid.new(queue))
    patch endpoint, headers: headers, params: { user_ids: [], manager_confirmation: { confirmed: true, review_token: token } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(team.members).to include(operator)
    expect(audits).to be_empty
  end

  it 'accepts an atomic replacement only when the proposed agent really retains both native authorities' do
    replacement = create(:user, :contact_center_eligible, account: account)
    peer = account.account_users.find_by!(user: replacement)
    peer.update!(custom_role: member.custom_role)
    team.add_members([replacement.id])
    source = account.jrc_crm_user_business_units.create!(user: replacement, team: team, scope: 'GROUP', structure_managed: true)
    team.remove_members([replacement.id])
    JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: peer)
    patch endpoint, headers: headers, params: { user_ids: [replacement.id.to_s] }, as: :json
    expect(response).to have_http_status(:ok)
    expect(team.team_members.reload.pluck(:user_id)).to eq([replacement.id])
    expect(audits).to be_empty
    expect(membership.reload).to be_active
    expect(source.reload).to be_active
    expect(JrcCrm::CorporateCoverage.new(account: account, user: replacement)).to be_group
  end

  it 'reports the full loss when one roster operation removes multiple eligible agents from the same queue' do
    other = create(:user, :contact_center_eligible, account: account)
    peer = account.account_users.find_by!(user: other)
    peer.update!(custom_role: member.custom_role)
    team.add_members([other.id])
    account.jrc_crm_user_business_units.create!(user: other, team: team, scope: 'GROUP', structure_managed: true)
    JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: peer)
    patch endpoint, headers: headers, params: { user_ids: [] }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('review', 'queues')).to contain_exactly(
      a_hash_including('queue_id' => queue.id.to_s, 'previous_count' => 2, 'remaining_count' => 0)
    )
    expect(team.members.pluck(:id)).to contain_exactly(operator.id, other.id)
    expect(audits).to be_empty
  end

  it 'preserves native roster compatibility when the Call Center feature is disabled' do
    account.disable_features!('jrc_contact_center')
    patch endpoint, headers: headers, params: { user_ids: [] }, as: :json
    expect(response).to have_http_status(:ok)
    expect(team.team_members.reload).to be_empty
    expect(audits).to be_empty
  end

  it 'cannot reach a foreign account team or leak its queue details' do
    other = create(:user, :contact_center_eligible, account: create(:account), role: :administrator)
    patch endpoint, headers: other.create_new_auth_token, params: { user_ids: [] }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(queue.name)
    expect(team.members).to include(operator)
  end

  it 'keeps a repeated already-applied removal idempotent without creating a second review audit' do
    patch endpoint, headers: headers, params: { user_ids: [] }, as: :json
    token = response.parsed_body.fetch('review').fetch('review_token')
    payload = { user_ids: [], manager_confirmation: { confirmed: true, review_token: token } }
    patch endpoint, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:ok)
    patch endpoint, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:ok)
    expect(audits.count).to eq(1)
  end

  it 'reuses native audit history and denies its detail after corporate coverage moves away from the recorded queue' do
    manager.update!(custom_role: create(:custom_role, account: account, permissions: JrcContactCenter::ModulePolicy::PERMISSIONS))
    patch endpoint, headers: headers, params: { user_ids: [] }, as: :json
    token = response.parsed_body.fetch('review').fetch('review_token')
    patch endpoint, headers: headers, params: { user_ids: [], manager_confirmation: { confirmed: true, review_token: token } }, as: :json
    expect(response).to have_http_status(:ok)
    history = "/api/v1/accounts/#{account.id}/jrc_contact_center/configuration_audits"
    get history, headers: headers, params: { resource_type: 'queue', resource_id: queue.id, history: true }
    expect(response).to have_http_status(:ok)
    event = response.parsed_body.fetch('items').find { |row| row['manager_review'] }
    expect(event.fetch('manager_review')).to include('kind' => 'jrc_cc_team_roster_withdrawal_v1', 'team_id' => team.id.to_s)
    expect(event.to_json).not_to include(token)
    another = account.jrc_crm_business_units.create!(operating_company: company, code: 'DENIED', name: 'SYNTHETIC other business')
    account.jrc_crm_user_business_units.find_by!(user: actor).update!(scope: 'BUSINESS_UNIT', company: company, business_unit: another)
    get "#{history}/#{event.fetch('id')}", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(queue.name)
    expect(audits.count).to eq(1)
  end
end

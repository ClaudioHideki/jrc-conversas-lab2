require 'rails_helper'

RSpec.describe 'Native whole-team deletion manager review', type: :request do
  include ActiveSupport::Testing::TimeHelpers
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:manager) { account.account_users.find_by!(user: actor) }
  let(:operator) { create(:user, :contact_center_eligible, account: account) }
  let(:member) { account.account_users.find_by!(user: operator) }
  let(:team) { create(:team, account: account) }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC deletion issuer', relationship_type: 'internal') }
  let(:business) { account.jrc_crm_business_units.create!(operating_company: company, code: 'DELETE', name: 'SYNTHETIC business') }
  let(:unit) do
    JrcContactCenter::Unit.create!(account: account, code: 'DELETE', name: 'SYNTHETIC unit', kind: 'sac',
                                 settings: { issuer_company_id: company.id, business_unit_id: business.id })
  end
  let(:queue) { JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'DELETE', name: 'SYNTHETIC last-agent queue') }
  let!(:membership) { JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/teams/#{team.id}" }
  let!(:headers) { actor.create_new_auth_token }
  let(:audits) { Audited.audit_class.where(auditable: queue, action: 'update', comment: JrcContactCenter::ConfigurationAudit::COMMENT) }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'GROUP', structure_managed: true)
    account.jrc_crm_user_business_units.create!(user: operator, scope: 'GROUP', structure_managed: true)
    member.update!(custom_role: create(:custom_role, account: account, permissions: []))
    team.add_members([operator.id])
    JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: %w[jrc_contact_center_view jrc_contact_center_operate])
  end

  after { Current.reset }

  it 'blocks unreviewed whole-team deletion before touching native members, grants, cache or queue audit' do
    original = team.team_members.sole.id
    expect(Redis::Alfred).not_to receive(:setex).with("idb-cache-key-account-#{account.id}-team", anything, anything)
    delete endpoint, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.parsed_body.dig('review', 'operation')).to eq('delete_team')
    expect(team.team_members.reload.pluck(:id)).to eq([original])
    expect(JrcContactCenter::AccessGrant.exists?(account: account, team: team)).to be(true)
    expect(audits).to be_empty
  end

  it 'requires the literal manager confirmation and persists the scoped receipt audit with the native deletion' do
    delete endpoint, headers: headers, as: :json
    token = response.parsed_body.fetch('review').fetch('review_token')
    delete endpoint, headers: headers, params: { manager_confirmation: { confirmed: true, review_token: token } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(account.teams.exists?(team.id)).to be(false)
    expect(membership.reload).to be_active
    expect(JrcContactCenter::AccessGrant.exists?(account: account, team_id: team.id)).to be(false)
    expect(audits.sole.audited_changes.fetch('manager_review')).to include(
      'kind' => 'jrc_cc_team_deletion_v1', 'team_id' => team.id.to_s, 'operation' => 'delete_team',
      'account_user_id' => manager.id.to_s, 'previous_count' => 1, 'remaining_count' => 0
    )
    expect(audits.sole.audited_changes.to_json).not_to include(token)
    expect(account.jrc_crm_user_business_units.find_by!(user: operator)).to be_active
  end

  [false, 'true', nil].each do |confirmed|
    it "does not treat #{confirmed.inspect} as the manager's explicit deletion approval" do
      delete endpoint, headers: headers, as: :json
      token = response.parsed_body.fetch('review').fetch('review_token')
      delete endpoint, headers: headers, params: { manager_confirmation: { confirmed: confirmed, review_token: token } }, as: :json
      expect(response).to have_http_status(:conflict)
      expect(account.teams.exists?(team.id)).to be(true)
      expect(audits).to be_empty
    end
  end

  it 'does not accept a member-removal receipt as authority to delete the team entity' do
    patch "#{endpoint}/team_members", headers: headers, params: { user_ids: [] }, as: :json
    token = response.parsed_body.fetch('review').fetch('review_token')
    delete endpoint, headers: headers, params: { manager_confirmation: { confirmed: true, review_token: token } }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('team_deletion_confirmation_required')
    expect(account.teams.exists?(team.id)).to be(true)
    expect(audits).to be_empty
  end

  it 'does not accept the deletion receipt as a member-removal confirmation either' do
    delete endpoint, headers: headers, as: :json
    token = response.parsed_body.fetch('review').fetch('review_token')
    patch "#{endpoint}/team_members", headers: headers,
                                      params: { user_ids: [], manager_confirmation: { confirmed: true, review_token: token } }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(team.members).to include(operator)
    expect(audits).to be_empty
  end

  it 'binds the deletion to the actual team revision instead of accepting a review for an old team name' do
    delete endpoint, headers: headers, as: :json
    token = response.parsed_body.fetch('review').fetch('review_token')
    team.update!(name: 'SYNTHETIC renamed team')
    delete endpoint, headers: headers, params: { manager_confirmation: { confirmed: true, review_token: token } }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('review', 'team_name')).to eq(team.name)
    expect(account.teams.exists?(team.id)).to be(true)
    expect(audits).to be_empty
  end

  it 'requires a new review when the real roster changed' do
    delete endpoint, headers: headers, as: :json
    token = response.parsed_body.fetch('review').fetch('review_token')
    another = create(:user, account: account)
    team.add_members([another.id])
    delete endpoint, headers: headers, params: { manager_confirmation: { confirmed: true, review_token: token } }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(team.members.pluck(:id)).to contain_exactly(operator.id, another.id)
    expect(audits).to be_empty
  end

  it 'expires a deletion receipt and never turns it into an access grant' do
    delete endpoint, headers: headers, as: :json
    token = response.parsed_body.fetch('review').fetch('review_token')
    travel 11.minutes do
      delete endpoint, headers: headers, params: { manager_confirmation: { confirmed: true, review_token: token } }, as: :json
      expect(response).to have_http_status(:conflict)
    end
    expect(account.teams.exists?(team.id)).to be(true)
    expect(audits).to be_empty
  end

  it 'denies a different manager even when the signed receipt is otherwise valid' do
    delete endpoint, headers: headers, as: :json
    token = response.parsed_body.fetch('review').fetch('review_token')
    other = create(:user, :contact_center_eligible, account: account, role: :administrator)
    account.jrc_crm_user_business_units.create!(user: other, scope: 'GROUP', structure_managed: true)
    delete endpoint, headers: other.create_new_auth_token,
                     params: { manager_confirmation: { confirmed: true, review_token: token } }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(account.teams.exists?(team.id)).to be(true)
    expect(audits).to be_empty
  end

  it 'does not expose the last-agent review to a manager without all affected corporate units' do
    account.jrc_crm_user_business_units.find_by!(user: actor).update!(active: false)
    delete endpoint, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(queue.name)
    expect(account.teams.exists?(team.id)).to be(true)
    expect(audits).to be_empty
  end

  it 'does not allow a foreign-account administrator to delete or inspect the target team' do
    other = create(:user, :contact_center_eligible, account: create(:account), role: :administrator)
    delete endpoint, headers: other.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(queue.name)
    expect(account.teams.exists?(team.id)).to be(true)
  end

  it 'preserves a separate direct operator grant without requesting a false empty-queue review' do
    JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member).update!(
      allowed: %w[jrc_contact_center_view jrc_contact_center_operate]
    )
    delete endpoint, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(account.teams.exists?(team.id)).to be(false)
    expect(membership.reload).to be_active
    expect(audits).to be_empty
  end

  it 'does not destroy the corporate hierarchy or keep a phantom audit if a native foreign key rejects the delete' do
    source = account.jrc_crm_team_scopes.create!(team: team, scope: 'GROUP')
    delete endpoint, headers: headers, as: :json
    token = response.parsed_body.fetch('review').fetch('review_token')
    delete endpoint, headers: headers, params: { manager_confirmation: { confirmed: true, review_token: token } }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('team_in_use')
    expect(source.reload).to be_active
    expect(team.reload.members).to include(operator)
    expect(JrcContactCenter::AccessGrant.exists?(account: account, team: team)).to be(true)
    expect(audits).to be_empty
  end

  it 'rolls back every native deletion consequence if its mandatory queue audit fails' do
    delete endpoint, headers: headers, as: :json
    token = response.parsed_body.fetch('review').fetch('review_token')
    allow(JrcContactCenter::ConfigurationAudit).to receive(:write_team_withdrawal!).and_raise(ActiveRecord::RecordInvalid.new(queue))
    delete endpoint, headers: headers, params: { manager_confirmation: { confirmed: true, review_token: token } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(team.reload.members).to include(operator)
    expect(JrcContactCenter::AccessGrant.exists?(account: account, team: team)).to be(true)
    expect(audits).to be_empty
  end

  it 'preserves the native no-Call-Center deletion contract without fabricating a queue audit' do
    account.disable_features!('jrc_contact_center')
    delete endpoint, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(account.teams.exists?(team.id)).to be(false)
    expect(audits).to be_empty
  end
  it 'retains eligibility provided by a separate existing team without requesting an unnecessary deletion receipt' do
    other = create(:team, account: account)
    other.add_members([operator.id])
    JrcContactCenter::AccessGrant.create!(account: account, team: other, allowed: %w[jrc_contact_center_view jrc_contact_center_operate])
    delete endpoint, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(other.reload.members).to include(operator)
    expect(membership.reload).to be_active
    expect(audits).to be_empty
  end

  it 'does not describe an inactive queue as operationally losing its last configured agent' do
    queue.update!(status: 'inactive')
    before_count = audits.count
    delete endpoint, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(account.teams.exists?(team.id)).to be(false)
    expect(audits.count).to eq(before_count)
  end

  it 'rejects malformed confirmation and forged receipts without mutating the native team' do
    ['not-an-object', { confirmed: true, review_token: 'forged' }].each do |confirmation|
      delete endpoint, headers: headers, params: { manager_confirmation: confirmation }, as: :json
      expect(response).to have_http_status(:conflict)
    end
    expect(team.reload.members).to include(operator)
    expect(audits).to be_empty
  end

  it 'reauthorizes the native administrator role rather than treating the deletion receipt as permission' do
    delete endpoint, headers: headers, as: :json
    token = response.parsed_body.fetch('review').fetch('review_token')
    manager.update!(role: :agent)
    delete endpoint, headers: headers, params: { manager_confirmation: { confirmed: true, review_token: token } }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(queue.name)
    expect(account.teams.exists?(team.id)).to be(true)
    expect(audits).to be_empty
  end

  it 'invalidates the deletion review when the operational unit revision changes' do
    delete endpoint, headers: headers, as: :json
    token = response.parsed_body.fetch('review').fetch('review_token')
    unit.update!(name: 'SYNTHETIC unit changed after review')
    delete endpoint, headers: headers, params: { manager_confirmation: { confirmed: true, review_token: token } }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(account.teams.exists?(team.id)).to be(true)
    expect(audits).to be_empty
  end
end

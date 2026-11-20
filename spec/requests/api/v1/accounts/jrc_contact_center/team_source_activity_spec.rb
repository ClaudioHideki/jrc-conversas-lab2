require 'rails_helper'

RSpec.describe 'Call Center team source activity without changing shared teams', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let!(:headers) { actor.create_new_auth_token }
  let(:manager) { account.account_users.find_by!(user: actor) }
  let(:role) { create(:custom_role, account: account, permissions: JrcContactCenter::ModulePolicy::PERMISSIONS) }
  let(:recipient) { create(:user, :contact_center_eligible, account: account) }
  let(:member) { account.account_users.find_by!(user: recipient) }
  let(:team) { create(:team, account: account) }
  let!(:grant) { JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: ['jrc_contact_center_monitor']) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/access_authorizations/teams/#{team.id}" }
  let(:authority) { JrcContactCenter::AccessAuthorization.new(context: { account: account, account_user: manager, user: actor }) }
  let(:context) { { account: account, account_user: member, user: recipient } }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
    manager.update!(custom_role: role)
    member.update!(custom_role: create(:custom_role, account: account, permissions: ['jrc_contact_center_view']))
    team.add_members([recipient.id])
  end

  it 'treats a team without a state row as active without creating any new source or grant' do
    expect { get endpoint, headers: headers }.not_to change(JrcContactCenter::TeamState, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item')).to include('active' => true, 'allowed' => ['jrc_contact_center_monitor'])
    expect(JrcContactCenter::ModulePolicy.new(context, :contact_center).monitor?).to be(true)
  end

  it 'keeps the exact v1 team revision when no explicit state exists' do
    legacy = [team.attributes, JrcContactCenter::ConfigurationRevision.token(grant), team.team_members.order(:user_id).pluck(:user_id)]
    expect(authority.revision(team, grant)).to eq(Digest::SHA256.hexdigest(legacy.to_json))
    patch endpoint, headers: headers, params: { authorization: { active: true }, expected_revision: authority.revision(team, grant) }, as: :json
    expect(response).to have_http_status(:ok)
    expect(JrcContactCenter::TeamState.where(account: account, team: team)).to be_empty
    expect(authority.revision(team.reload, grant.reload)).to eq(Digest::SHA256.hexdigest(legacy.to_json))
  end

  it 'suspends only this inherited source and keeps native roster, individual eligibility and other team rights' do
    other = create(:team, account: account)
    other.add_members([recipient.id])
    JrcContactCenter::AccessGrant.create!(account: account, team: other, allowed: ['jrc_contact_center_audit'])
    individual = JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member).attributes
    patch endpoint, headers: headers, params: { authorization: { active: false }, expected_revision: authority.revision(team, grant) }, as: :json
    expect(response).to have_http_status(:ok)
    expect(JrcContactCenter::ModulePolicy.new(context, :contact_center).effective_permissions).to include('jrc_contact_center_audit')
    expect(JrcContactCenter::ModulePolicy.new(context, :contact_center).monitor?).to be(false)
    expect(team.team_members.pluck(:user_id)).to eq([recipient.id])
    expect(JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member).attributes).to eq(individual)
    expect(grant.reload.allowed).to eq(['jrc_contact_center_monitor'])
  end

  it 'preserves an individually granted right even when the same inherited team right is suspended' do
    JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member).update!(allowed: ['jrc_contact_center_monitor'])
    patch endpoint, headers: headers, params: { authorization: { active: false }, expected_revision: authority.revision(team, grant) }, as: :json
    expect(response).to have_http_status(:ok)
    expect(JrcContactCenter::ModulePolicy.new(context, :contact_center).monitor?).to be(true)
    expect(team.members).to include(recipient)
  end

  it 'restores only reviewed inherited rights without changing explicit individual denials or eligibility' do
    JrcContactCenter::TeamState.create!(account: account, team: team, active: false)
    individual = JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member)
    individual.update!(eligible: false, denied: ['jrc_contact_center_monitor'])
    patch endpoint, headers: headers, params: { authorization: { active: true }, expected_revision: authority.revision(team, grant) }, as: :json
    expect(response).to have_http_status(:ok)
    expect(JrcContactCenter::ModulePolicy.new(context, :contact_center).effective_permissions).to eq([])
    expect(individual.reload).to have_attributes(eligible: false, denied: ['jrc_contact_center_monitor'])
  end

  it 'rejects restoration of a latent right above the current actor authority before writing status or audits' do
    JrcContactCenter::TeamState.create!(account: account, team: team, active: false)
    role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_administer])
    patch endpoint, headers: headers, params: { authorization: { active: true }, expected_revision: authority.revision(team, grant) }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::TeamState.find_by!(team: team)).not_to be_active
    expect(JrcContactCenter::ModulePolicy.new(context, :contact_center).monitor?).to be(false)
  end

  it 'does not reactivate a suspended team when shared membership is added by a native administrator' do
    JrcContactCenter::TeamState.create!(account: account, team: team, active: false)
    role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_administer])
    another = create(:user, :contact_center_eligible, account: account)
    another.account_users.find_by!(account: account).update!(custom_role: create(:custom_role, account: account, permissions: []))
    post "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members", headers: headers, params: { user_ids: [another.id] }, as: :json
    expect(response).to have_http_status(:ok)
    expect(team.members).to include(another)
    expect(JrcContactCenter::TeamState.find_by!(team: team)).not_to be_active
    expect(authority.effective(another.account_users.find_by!(account: account))).to eq([])
  end

  it 'detects deactivate-reactivate ABA even when the allowed capabilities and shared roster did not change' do
    old = authority.revision(team, grant)
    state = JrcContactCenter::TeamState.create!(account: account, team: team, active: false)
    state.update!(active: true)
    patch endpoint, headers: headers, params: { authorization: { active: false }, expected_revision: old }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(state.reload).to be_active
    expect(grant.reload.allowed).to eq(['jrc_contact_center_monitor'])
  end

  it 'includes inactive origins as history but does not present them as effective inherited permissions' do
    JrcContactCenter::TeamState.create!(account: account, team: team, active: false)
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/access_authorizations/users/#{member.id}", headers: headers
    expect(response).to have_http_status(:ok)
    item = response.parsed_body.fetch('item')
    expect(item.fetch('inherited')).not_to include('jrc_contact_center_monitor')
    expect(item.dig('origins', 'teams')).to contain_exactly(
      a_hash_including('id' => team.id, 'active' => false, 'configured_permissions' => ['jrc_contact_center_monitor'], 'permissions' => [])
    )
    expect(item.fetch('eligible')).to be(true)
  end

  it 'filters active and inactive team states with normal pagination and native account scoping' do
    JrcContactCenter::TeamState.create!(account: account, team: team, active: false)
    create(:team, account: account)
    foreign = create(:team, account: create(:account))
    JrcContactCenter::TeamState.create!(account: foreign.account, team: foreign, active: false)
    get endpoint.rpartition('/').first, headers: headers, params: { status: 'inactive', per_page: 1 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([team.id])
    expect(response.parsed_body.dig('meta', 'total')).to eq(1)
    get endpoint.rpartition('/').first, headers: headers, params: { status: 'active' }
    expect(response.parsed_body.fetch('items').pluck('id')).not_to include(team.id, foreign.id)
  end

  [nil, 0, 'false', [], {}].each do |invalid|
    it "rejects non-boolean team state #{invalid.inspect} without creating a state" do
      patch endpoint, headers: headers, params: { authorization: { active: invalid }, expected_revision: authority.revision(team, grant) }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JrcContactCenter::TeamState.where(team: team)).to be_empty
    end
  end

  it 'rolls back a permission change and status together when mandatory native audit fails' do
    allow(JrcContactCenter::ConfigurationAudit).to receive(:write!).and_wrap_original do |original, record, **arguments|
      raise ActiveRecord::RecordInvalid, record if record.is_a?(JrcContactCenter::TeamState)

      original.call(record, **arguments)
    end
    patch endpoint, headers: headers,
                    params: { authorization: { active: false, allowed: [] }, expected_revision: authority.revision(team, grant) }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::TeamState.where(team: team)).to be_empty
    expect(grant.reload.allowed).to eq(['jrc_contact_center_monitor'])
  end

  it 'shows the module-local status in native administrative teams and filters it without deleting their shared membership' do
    JrcContactCenter::TeamState.create!(account: account, team: team, active: false)
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/administration/teams", headers: headers, params: { status: 'inactive', page: 1 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to contain_exactly(a_hash_including('id' => team.id, 'cc_active' => false))
    expect(team.members).to include(recipient)
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/administration/teams", headers: headers, params: { status: 'active', page: 1 }
    expect(response.parsed_body.fetch('items')).to be_empty
  end
end

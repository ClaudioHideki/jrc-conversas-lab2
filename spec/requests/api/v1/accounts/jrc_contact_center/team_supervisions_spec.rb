require 'rails_helper'

RSpec.describe 'Call Center native team supervision metadata', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator, name: 'SYNTHETIC managing admin') }
  let(:actor_link) { account.account_users.find_by!(user: actor) }
  let(:actor_role) { create(:custom_role, account: account, permissions: JrcContactCenter::ModulePolicy::PERMISSIONS) }
  let(:headers) { actor.create_new_auth_token }
  let(:recipient) { create(:user, :contact_center_eligible, account: account, role: :agent, name: 'SYNTHETIC eligible supervisor') }
  let(:member) { account.account_users.find_by!(user: recipient) }
  let(:recipient_role) { create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_supervise]) }
  let(:team) { create(:team, account: account) }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC issuer', relationship_type: 'internal') }
  let(:unit) { account.jrc_crm_business_units.create!(name: 'SYNTHETIC unit', code: 'unit', company_id: company.id) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/team_supervisions/#{team.id}" }
  let(:values) { { primary_account_user_id: member.id.to_s, additional_account_user_ids: [] } }
  let(:additional_member) do
    user = create(:user, :contact_center_eligible, account: account, role: :administrator)
    account.jrc_crm_user_business_units.create!(user: user, scope: 'BUSINESS_UNIT', business_unit: unit, structure_managed: true)
    account.account_users.find_by!(user: user)
  end

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
    actor_link.update!(custom_role: actor_role)
    member.update!(custom_role: recipient_role)
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'GROUP', structure_managed: true)
    account.jrc_crm_user_business_units.create!(user: recipient, scope: 'BUSINESS_UNIT', business_unit: unit, structure_managed: true)
    account.jrc_crm_team_scopes.create!(team: team, scope: 'BUSINESS_UNIT', business_unit: unit)
  end

  def current_state
    get endpoint, headers: headers
    expect(response).to have_http_status(:ok)
    response.parsed_body.fetch('item')
  end

  it 'reads actual empty metadata without creating a primary, membership or grant' do
    count = JrcContactCenter::AccessGrant.count
    state = current_state
    expect(state).to include('id' => team.id.to_s, 'primary_account_user_id' => nil, 'additional_account_user_ids' => [], 'supervisors' => [])
    expect(state.fetch('revision')).to match(/\A[0-9a-f]{64}\z/)
    expect(response.headers['Cache-Control']).to eq('no-store')
    expect(JrcContactCenter::TeamSupervision.where(team: team)).to be_empty
    expect(JrcContactCenter::AccessGrant.count).to eq(count)
  end

  it 'saves and reloads primary/additional native members without adding distribution, recording or Nico rights' do
    extra = additional_member
    revision = current_state.fetch('revision')
    context = { account: account, account_user: member, user: recipient }
    permissions = JrcContactCenter::ModulePolicy.new(context, :contact_center).effective_permissions
    expect(permissions).to match_array(%w[jrc_contact_center_view jrc_contact_center_supervise jrc_contact_center_reports])
    counts = [TeamMember.count, JrcContactCenter::QueueMembership.count, JrcContactCenter::AccessGrant.count]
    values[:additional_account_user_ids] = [extra.id.to_s]
    patch endpoint, headers: headers, params: { supervision: values, expected_revision: revision }, as: :json
    expect(response).to have_http_status(:ok)
    state = current_state
    expect(state).to include('primary_account_user_id' => member.id.to_s, 'additional_account_user_ids' => [extra.id.to_s])
    expect(state.fetch('supervisors').map { |row| row.fetch('eligible') }).to eq([true, true])
    expect([TeamMember.count, JrcContactCenter::QueueMembership.count, JrcContactCenter::AccessGrant.count]).to eq(counts)
    policy = JrcContactCenter::ModulePolicy.new(context, :contact_center)
    expect(policy.effective_permissions).to match_array(permissions)
    expect(policy).not_to be_quality_review
  end

  it 'changes the principal atomically while preserving the old person as an explicit additional supervisor' do
    extra = additional_member
    revision = current_state.fetch('revision')
    values[:additional_account_user_ids] = [extra.id.to_s]
    patch endpoint, headers: headers, params: { supervision: values, expected_revision: revision }, as: :json
    expect(response).to have_http_status(:ok)
    revision = response.parsed_body.dig('item', 'revision')
    values.merge!(primary_account_user_id: extra.id.to_s, additional_account_user_ids: [member.id.to_s])
    patch endpoint, headers: headers, params: { supervision: values, expected_revision: revision }, as: :json
    expect(response).to have_http_status(:ok)
    expect(JrcContactCenter::TeamSupervision.where(team: team, kind: 'primary').sole.account_user_id).to eq(extra.id)
    expect(JrcContactCenter::TeamSupervision.where(team: team, kind: 'additional').sole.account_user_id).to eq(member.id)
  end

  it 'keeps a same-value reviewed no-op idempotent without replacing IDs or producing duplicate audit events' do
    revision = current_state.fetch('revision')
    patch endpoint, headers: headers, params: { supervision: values, expected_revision: revision }, as: :json
    expect(response).to have_http_status(:ok)
    state = response.parsed_body.fetch('item')
    ids = JrcContactCenter::TeamSupervision.where(team: team).pluck(:id)
    count = Audited.audit_class.where(auditable_type: 'JrcContactCenter::TeamSupervision').count
    patch endpoint, headers: headers, params: { supervision: values, expected_revision: state.fetch('revision') }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('item', 'revision')).to eq(state.fetch('revision'))
    expect(JrcContactCenter::TeamSupervision.where(team: team).pluck(:id)).to eq(ids)
    expect(Audited.audit_class.where(auditable_type: 'JrcContactCenter::TeamSupervision').count).to eq(count)
  end

  it 'rejects stale and missing revisions without overwriting the saved principal' do
    revision = current_state.fetch('revision')
    patch endpoint, headers: headers, params: { supervision: values, expected_revision: revision }, as: :json
    expect(response).to have_http_status(:ok)
    empty = { primary_account_user_id: nil, additional_account_user_ids: [] }
    patch endpoint, headers: headers, params: { supervision: empty, expected_revision: revision }, as: :json
    expect(response).to have_http_status(:conflict)
    patch endpoint, headers: headers, params: { supervision: empty }, as: :json
    expect(response).to have_http_status(:precondition_required)
    expect(JrcContactCenter::TeamSupervision.where(team: team).sole.account_user_id).to eq(member.id)
  end

  it 'does not let a plain administrator bypass the explicit native administer requirement' do
    actor_link.update!(custom_role: nil)
    get endpoint, headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::TeamSupervision.where(team: team)).to be_empty
  end

  it 'reauthorizes the actor profile before writing rather than trusting the earlier successful read' do
    revision = current_state.fetch('revision')
    actor_role.update!(permissions: ['jrc_contact_center_view'])
    patch endpoint, headers: headers, params: { supervision: values, expected_revision: revision }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::TeamSupervision.where(team: team)).to be_empty
  end

  it 'does not expose global team/member configuration after the actor loses explicit group coverage' do
    account.jrc_crm_user_business_units.find_by!(user: actor, scope: 'GROUP').update!(active: false)
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', business_unit: unit, structure_managed: true)
    get "#{endpoint}/candidates", headers: headers
    expect(response).to have_http_status(:unauthorized)
    get endpoint, headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'refuses a pending recipient without activating eligibility or interpreting online presence as authority' do
    revision = current_state.fetch('revision')
    grant = JrcContactCenter::AccessGrant.find_by!(account_user: member)
    grant.update!(eligible: false)
    recipient.update!(availability: :online)
    patch endpoint, headers: headers, params: { supervision: values, expected_revision: revision }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('ineligible_team_supervisor')
    expect(grant.reload).not_to be_eligible
    expect(JrcContactCenter::TeamSupervision.where(team: team)).to be_empty
  end

  it 'refuses an unconfirmed selected user while preserving the existing explicit eligibility grant' do
    revision = current_state.fetch('revision')
    recipient.update!(confirmed_at: nil)
    patch endpoint, headers: headers, params: { supervision: values, expected_revision: revision }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::AccessGrant.find_by!(account_user: member)).to be_eligible
    expect(JrcContactCenter::TeamSupervision.where(team: team)).to be_empty
  end

  it 'refuses an explicit individual supervision denial even when a supervisor profile still allows it' do
    revision = current_state.fetch('revision')
    JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(denied: ['jrc_contact_center_supervise'])
    patch endpoint, headers: headers, params: { supervision: values, expected_revision: revision }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::TeamSupervision.where(team: team)).to be_empty
  end

  it 'does not substitute account-wide access for the selected person coverage after a native source withdrawal' do
    revision = current_state.fetch('revision')
    account.jrc_crm_user_business_units.find_by!(user: recipient).update!(active: false)
    patch endpoint, headers: headers, params: { supervision: values, expected_revision: revision }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::TeamSupervision.where(team: team)).to be_empty
  end

  it 'does not map a unit-only supervisor to a company-wide team by an overlapping company ID' do
    account.jrc_crm_team_scopes.find_by!(team: team).update!(scope: 'COMPANY', company: company, business_unit: nil)
    revision = current_state.fetch('revision')
    patch endpoint, headers: headers, params: { supervision: values, expected_revision: revision }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::TeamSupervision.where(team: team)).to be_empty
  end

  it 'rejects another account team and member before exposing names or changing any records' do
    revision = current_state.fetch('revision')
    other = create(:account)
    foreign_team = create(:team, account: other)
    foreign_user = create(:user, account: other)
    foreign_member = other.account_users.find_by!(user: foreign_user)
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/team_supervisions/#{foreign_team.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    values[:primary_account_user_id] = foreign_member.id.to_s
    patch endpoint, headers: headers, params: { supervision: values, expected_revision: revision }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcContactCenter::TeamSupervision.where(team: team)).to be_empty
  end

  it 'rejects permission or membership keys rather than silently accepting operational effects' do
    revision = current_state.fetch('revision')
    values[:allowed] = ['jrc_contact_center_quality_review']
    patch endpoint, headers: headers, params: { supervision: values, expected_revision: revision }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('invalid_team_supervision')
    expect(JrcContactCenter::TeamSupervision.where(team: team)).to be_empty
  end

  it 'uses fresh eligibility and native names for paginated candidate search without listing another account' do
    get "#{endpoint}/candidates", headers: headers, params: { q: recipient.name, per_page: 1 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to include(include('account_user_id' => member.id.to_s, 'eligible' => true))
    expect(response.parsed_body.dig('meta', 'per_page')).to eq(1)
    JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(eligible: false)
    get "#{endpoint}/candidates", headers: headers, params: { q: recipient.name }
    expect(response.parsed_body.fetch('items')).to include(
      include('account_user_id' => member.id.to_s, 'eligible' => false, 'reason' => 'permission')
    )
    expect(JrcContactCenter::TeamSupervision.where(team: team)).to be_empty
  end

  it 'paginates a populated native candidate relation with a maximum of twenty and disjoint pages' do
    23.times { |index| create(:user, account: account, name: "SYNTHETIC candidate page #{index}") }
    get "#{endpoint}/candidates", headers: headers, params: { q: 'SYNTHETIC candidate page', per_page: 200 }
    first = response.parsed_body
    expect(response).to have_http_status(:ok)
    expect(first.fetch('meta')).to include('page' => 1, 'pages' => 2, 'per_page' => 20, 'total' => 23)
    expect(first.fetch('items').length).to eq(20)
    get "#{endpoint}/candidates", headers: headers, params: { q: 'SYNTHETIC candidate page', page: 2 }
    second = response.parsed_body.fetch('items')
    expect(second.length).to eq(3)
    expect(first.fetch('items').pluck('account_user_id') & second.pluck('account_user_id')).to be_empty
    expect(first.fetch('items').all? { |row| row.fetch('eligible') == false }).to be(true)
  end

  it 'preserves a canonical bigint team identity and returns actual supervision summaries in the existing team list' do
    exact = account.teams.create!(id: 9_007_199_254_740_993, name: 'SYNTHETIC bigint supervision team')
    JrcContactCenter::TeamSupervision.create!(account: account, team: exact, account_user: member, kind: 'primary')
    path = "/api/v1/accounts/#{account.id}/jrc_contact_center/access_authorizations/teams"
    get path, headers: headers, params: { q: exact.name }
    expect(response).to have_http_status(:ok)
    row = response.parsed_body.fetch('items').sole
    expect(row).to include('team_identity' => '9007199254740993', 'primary_supervisor' => recipient.name, 'additional_supervisor_count' => 0)
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/team_supervisions/9007199254740993", headers: headers
    expect(response.parsed_body.dig('item', 'id')).to eq('9007199254740993')
  end

  it 'rolls back the entire reviewed replacement and audit if persisting a selected supervisor fails' do
    extra = additional_member
    revision = current_state.fetch('revision')
    patch endpoint, headers: headers, params: { supervision: values, expected_revision: revision }, as: :json
    expect(response).to have_http_status(:ok)
    revision = response.parsed_body.dig('item', 'revision')
    old = JrcContactCenter::TeamSupervision.where(team: team).pluck(:id, :account_user_id, :kind)
    count = Audited.audit_class.where(auditable_type: 'JrcContactCenter::TeamSupervision').count
    allow(JrcContactCenter::ConfigurationAudit).to receive(:write!).and_wrap_original do |original, target, **options|
      refused = target.is_a?(JrcContactCenter::TeamSupervision) && target.account_user_id == extra.id && options[:action] == 'create'
      raise 'SYNTHETIC persistence refusal' if refused

      original.call(target, **options)
    end
    values.merge!(primary_account_user_id: extra.id.to_s, additional_account_user_ids: [member.id.to_s])
    service = JrcContactCenter::TeamSupervisions.new(context: { account: account, account_user: actor_link, user: actor })
    expect { service.update!(id: team.id, attributes: values.stringify_keys, expected: revision) }
      .to raise_error(RuntimeError, 'SYNTHETIC persistence refusal')
    expect(JrcContactCenter::TeamSupervision.where(team: team).pluck(:id, :account_user_id, :kind)).to eq(old)
    expect(Audited.audit_class.where(auditable_type: 'JrcContactCenter::TeamSupervision').count).to eq(count)
  end

  it 'returns a correlated native audit detail and denies it after group coverage is withdrawn' do
    revision = current_state.fetch('revision')
    correlation = SecureRandom.uuid
    patch endpoint, headers: headers.merge('X-Request-ID' => correlation),
                    params: { supervision: values, expected_revision: revision }, as: :json
    expect(response).to have_http_status(:ok)
    audit = Audited.audit_class.where(auditable_type: 'JrcContactCenter::TeamSupervision', request_uuid: correlation).sole
    url = "/api/v1/accounts/#{account.id}/jrc_contact_center/configuration_audits/#{audit.id}"
    get url, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item')).to include('resource_type' => 'team_supervision', 'result' => 'recorded_locally')
    expect(response.body).not_to include(recipient.email)
    account.jrc_crm_user_business_units.find_by!(user: actor, scope: 'GROUP').update!(active: false)
    get url, headers: headers
    expect(response).to have_http_status(:not_found)
  end
end

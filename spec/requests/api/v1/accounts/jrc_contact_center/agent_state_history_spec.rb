require 'rails_helper'

RSpec.describe 'Call Center scoped operational state history', type: :request do
  let(:account) { create(:account) }
  let(:observer) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:role) { create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_supervise]) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, code: 'SYNTHETIC_HISTORY', name: 'SYNTHETIC history unit', kind: 'sac') }
  let(:queue) { JrcContactCenter::Queue.create!(account: account, unit: unit, name: 'SYNTHETIC history queue', code: 'SYNTHETIC_HISTORY') }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/agent_state_histories" }
  let(:event) do
    JrcContactCenter::AgentStateEvent.create!(
      account: account, account_user: member, queue: queue, state: 'paused',
      started_at: 2.minutes.ago, ended_at: 1.minute.ago, source: 'jrc_conversas',
      reason_code: 'SYNTHETIC_PRIVATE_REASON', external_event_id: 'SYNTHETIC_PRIVATE_COMMAND',
      metadata: { pause_justification: 'SYNTHETIC_PRIVATE_TEXT', provider_confirmed: false,
                  pause_definition: { name: 'SYNTHETIC_PRIVATE_DEFINITION' } }
    )
  end

  before do
    Current.reset
    account.enable_features!('jrc_contact_center', 'custom_roles')
    account.account_users.find_by!(user: observer).update!(custom_role: role)
    event
  end

  after { Current.reset }

  it 'returns only the explicit operational projection without mutating events or availability' do
    previous = event.attributes.deep_dup
    availability = member.availability
    get endpoint, headers: observer.create_new_auth_token
    row = response.parsed_body.fetch('items').sole
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(row).to include('id' => event.id.to_s, 'state' => 'paused', 'duration_seconds' => 60,
                           'agent_name' => actor.available_name, 'source' => 'local', 'provider_confirmed' => false)
    keys = %w[id account_user_id agent_name queue_id queue_name state started_at ended_at duration_seconds source provider_confirmed]
    expect(row.keys).to match_array(keys)
    expect(response.body).not_to include('SYNTHETIC_PRIVATE')
    expect([event.reload.attributes, member.reload.availability]).to eq([previous, availability])
  end

  it 'requires current supervisory or configuration authority rather than view or operate alone' do
    role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_operate])
    get endpoint, headers: observer.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(event.id.to_s.inspect, 'SYNTHETIC_PRIVATE')
  end

  it 'rechecks eligibility and the feature on each request' do
    JrcContactCenter::AccessGrant.find_by!(account: account, account_user: account.account_users.find_by!(user: observer)).update!(eligible: false)
    get endpoint, headers: observer.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    account.disable_features!('jrc_contact_center')
    get endpoint, headers: observer.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not grant authority from account or user parameters' do
    foreign = create(:account)
    foreign_user = create(:user, :contact_center_eligible, account: foreign, role: :administrator)
    get endpoint, params: { account_user_id: foreign.account_users.find_by!(user: foreign_user).id, user_id: foreign_user.id },
                  headers: observer.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to be_empty
    get "/api/v1/accounts/#{foreign.id}/jrc_contact_center/agent_state_histories", headers: observer.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'preserves native composite foreign keys against cross-account event members and queues' do
    foreign = create(:account)
    foreign_user = create(:user, account: foreign)
    foreign_member = foreign.account_users.find_by!(user: foreign_user)
    expect do
      JrcContactCenter::AgentStateEvent.transaction(requires_new: true) { event.update!(account_user_id: foreign_member.id) }
    end.to raise_error(ActiveRecord::InvalidForeignKey)
    event.reload
    foreign_unit = JrcContactCenter::Unit.create!(account: foreign, name: 'SYNTHETIC foreign', code: 'FOREIGN', kind: 'sac')
    foreign_queue = JrcContactCenter::Queue.create!(account: foreign, unit: foreign_unit, name: 'SYNTHETIC foreign', code: 'FOREIGN')
    expect do
      JrcContactCenter::AgentStateEvent.transaction(requires_new: true) { event.update!(queue_id: foreign_queue.id) }
    end.to raise_error(ActiveRecord::InvalidForeignKey)
    event.reload
    get endpoint, headers: observer.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([event.id.to_s])
    expect(event.account_user_id).to eq(member.id)
    expect(event.queue_id).to eq(queue.id)
  end

  it 'always paginates by default and orders equal timestamps deterministically' do
    21.times do
      JrcContactCenter::AgentStateEvent.create!(
        account: account, account_user: member, queue: queue, state: 'available',
        started_at: event.started_at, source: 'jrc_conversas'
      )
    end
    get endpoint, headers: observer.create_new_auth_token
    data = response.parsed_body
    expect(data.fetch('items').length).to eq(20)
    expect(data.fetch('meta')).to eq('page' => 1, 'per_page' => 20, 'total' => 22, 'pages' => 2)
    ids = data.fetch('items').pluck('id')
    expect(ids.map(&:to_i)).to eq(ids.map(&:to_i).sort.reverse)
    get endpoint, params: { page: 2 }, headers: observer.create_new_auth_token
    expect(response.parsed_body.fetch('items').pluck('id') & ids).to be_empty
    expect(response.parsed_body.fetch('items').length).to eq(2)
  end

  it 'filters by actual state, native queue and account membership and clears them without dropping scope' do
    get endpoint, params: { state: 'available' }, headers: observer.create_new_auth_token
    expect(response.parsed_body.fetch('items')).to be_empty
    get endpoint, params: { queue_id: queue.id, account_user_id: member.id, state: 'paused' }, headers: observer.create_new_auth_token
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([event.id.to_s])
    get endpoint, headers: observer.create_new_auth_token
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([event.id.to_s])
  end

  it 'uses the account timezone including both date boundaries' do
    account.update!(reporting_timezone: 'America/Sao_Paulo')
    event.update!(started_at: Time.iso8601('2026-11-18T02:59:59Z'), ended_at: Time.iso8601('2026-11-18T03:00:00Z'))
    get endpoint, params: { from: '2026-11-17', to: '2026-11-17' }, headers: observer.create_new_auth_token
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([event.id.to_s])
    expect(response.parsed_body.fetch('window')).to include('timezone' => 'America/Sao_Paulo')
    get endpoint, params: { from: '2026-11-18', to: '2026-11-18' }, headers: observer.create_new_auth_token
    expect(response.parsed_body.fetch('items')).to be_empty
  end

  [
    { state: 'bogus' }, { queue_id: '1 OR 1=1' }, { account_user_id: '9223372036854775808' },
    { state: ['paused'] }, { from: { invalid: 'date' } }, { from: '2026-02-30' }, { from: '2026-11-19', to: '2026-11-18' },
    { from: '2026-01-01', to: '2026-11-19' }, { from: '0000-01-01', to: '0000-01-02' }
  ].each do |filters|
    it "rejects malformed or unbounded filters #{filters.inspect} without returning private data" do
      get endpoint, params: filters, headers: observer.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).not_to include('SYNTHETIC_PRIVATE', actor.available_name)
    end
  end

  it 'searches the current authorized agent name with literal wildcard characters' do
    get endpoint, params: { q: actor.name }, headers: observer.create_new_auth_token
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([event.id.to_s])
    get endpoint, params: { q: '%' }, headers: observer.create_new_auth_token
    expect(response.parsed_body.fetch('items')).to be_empty
  end

  it 'computes an open duration from observation time without closing the real event or confirming the provider' do
    event.update!(ended_at: nil)
    travel_to(Time.zone.at((event.started_at + 61.seconds).to_f.ceil)) do
      get endpoint, headers: observer.create_new_auth_token
      row = response.parsed_body.fetch('items').sole
      expect(row).to include('duration_seconds' => 61, 'ended_at' => nil, 'provider_confirmed' => false)
      expect(event.reload.ended_at).to be_nil
    end
  end

  context 'with corporate coverage restricted to Unit A' do
    let(:company) { account.master_companies.create!(name: 'SYNTHETIC history company', relationship_type: 'internal') }
    let(:business) { JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: 'SYNTHETIC A', code: 'A') }

    before do
      unit.update!(settings: { issuer_company_id: company.id, business_unit_id: business.id })
      JrcCrm::UserBusinessUnit.create!(account: account, user: observer, scope: 'BUSINESS_UNIT', company: company,
                                       business_unit: business, active: true, structure_managed: true)
    end

    it 'returns only currently authorized queue events and excludes unmapped state events' do
      unbound = JrcContactCenter::AgentStateEvent.create!(
        account: account, account_user: member, state: 'offline', started_at: Time.current, source: 'jrc_conversas'
      )
      get endpoint, headers: observer.create_new_auth_token
      expect(response.parsed_body.fetch('items').pluck('id')).to eq([event.id.to_s])
      expect(response.body).not_to include(unbound.id.to_s.inspect)
      unit.update!(settings: {})
      get endpoint, headers: observer.create_new_auth_token
      expect(response.parsed_body.fetch('items')).to be_empty
    end

    it 'denies a queue outside coverage rather than treating its identifier as a grant' do
      unit.update!(settings: {})
      get endpoint, params: { queue_id: queue.id }, headers: observer.create_new_auth_token
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('SYNTHETIC_PRIVATE')
    end
  end
end

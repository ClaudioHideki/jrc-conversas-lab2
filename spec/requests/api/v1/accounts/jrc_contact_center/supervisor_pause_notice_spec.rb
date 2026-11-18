require 'rails_helper'

RSpec.describe 'Call Center authorized supervisor pause duration notice', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:observer) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC duration issuer', relationship_type: 'internal') }
  let(:business_units) do
    %w[A B].map do |code|
      JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: "SYNTHETIC duration #{code}", code: code)
    end
  end
  let(:units) do
    business_units.map do |business|
      JrcContactCenter::Unit.create!(account: account, code: business.code, name: business.name, kind: 'sac',
                                     settings: { issuer_company_id: company.id, business_unit_id: business.id })
    end
  end
  let(:queues) do
    units.map do |unit|
      queue = JrcContactCenter::Queue.create!(account: account, unit: unit, name: unit.name, code: unit.code)
      JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member)
      queue
    end
  end
  let(:pause_queue) { queues.first }
  let(:catalog) { JrcContactCenter::PauseCatalog.new(account: account) }
  let(:reason) do
    { 'code' => 'synthetic_duration', 'name' => 'SYNTHETIC PRIVATE duration name', 'category' => 'SYNTHETIC', 'active' => true,
      'minimum_minutes' => 0, 'default_minutes' => 1, 'maximum_minutes' => 1, 'unit_ids' => [pause_queue.unit_id], 'custom_role_ids' => [] }
  end
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/supervisor" }
  let(:event) do
    JrcContactCenter::AgentStateManager.new(account: account, account_user: member).transition(
      state: 'paused', reason_code: reason.fetch('code'), queue_id: pause_queue.id, command_id: SecureRandom.uuid, expected_state_version: '0',
      justification: 'SYNTHETIC PRIVATE pause duration explanation'
    )
  end

  before do
    Current.reset
    travel_to(Time.current.change(usec: 0))
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_supervise])
    account.account_users.find_by!(user: observer).update!(custom_role: role)
    JrcCrm::UserBusinessUnit.create!(account: account, user: observer, scope: 'BUSINESS_UNIT', company: company,
                                     business_unit: business_units.first, active: true, structure_managed: true)
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'GROUP', active: true, structure_managed: true)
    queues
    catalog.update!({ 'enforced' => true, 'entries' => [reason] }, expected_revision: catalog.revision, activation_confirmed: true)
    event
  end

  after do
    travel_back
    Current.reset
  end

  it 'exposes only duration and an exceeded flag without resuming availability or exposing private definition/text' do
    previous = event.attributes.deep_dup
    travel_to(event.started_at + 61.seconds) do
      get endpoint, headers: observer.create_new_auth_token
      expect(response).to have_http_status(:ok)
      data = response.parsed_body.fetch('agents').sole
      expect(data.fetch('pause_notice')).to eq('elapsed_seconds' => 61, 'exceeded' => true)
      expect(data.fetch('state')).to eq('paused')
      expect(response.body).not_to include('SYNTHETIC PRIVATE duration name', 'SYNTHETIC PRIVATE pause duration explanation')
      expect(data).not_to have_key('pause_definition')
      expect(event.reload.attributes).to eq(previous)
      expect(member.reload.availability).to eq('busy')
    end
  end

  it 'keeps a real zero and the exact informational threshold distinct from an exceeded pause' do
    [0, 60].each do |elapsed|
      travel_to(event.started_at + elapsed.seconds) do
        get endpoint, headers: observer.create_new_auth_token
        expect(response.parsed_body.fetch('agents').sole.fetch('pause_notice')).to eq('elapsed_seconds' => elapsed, 'exceeded' => false)
      end
    end
  end

  it 'uses the immutable event limit rather than changing an existing pause when the catalog changes' do
    previous = event.attributes.deep_dup
    catalog.update!({ 'enforced' => true, 'entries' => [reason.merge('maximum_minutes' => 100)] }, expected_revision: catalog.revision)
    travel_to(event.started_at + 61.seconds) do
      get endpoint, headers: observer.create_new_auth_token
      expect(response.parsed_body.fetch('agents').sole.dig('pause_notice', 'exceeded')).to be(true)
      expect(event.reload.attributes).to eq(previous)
    end
  end

  it 'does not derive a duration notice after the operator loses current operating eligibility' do
    JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member).update!(eligible: false)
    get endpoint, headers: observer.create_new_auth_token
    expect(response.parsed_body.fetch('agents').sole.fetch('pause_notice')).to be_nil
  end

  it 'does not derive a duration notice after the current queue membership is withdrawn' do
    JrcContactCenter::QueueMembership.find_by!(account: account, account_user: member, queue: pause_queue).update!(active: false)
    get endpoint, headers: observer.create_new_auth_token
    expect(response.parsed_body.fetch('agents').sole.fetch('pause_notice')).to be_nil
  end

  it 'does not invent an informational limit for an external provider pause without a native local definition' do
    JrcContactCenter::AgentStateManager.new(account: account, account_user: member).record_provider_event(
      state: 'paused', occurred_at: event.started_at + 1.second, external_event_id: SecureRandom.uuid,
      provider: 'synthetic-provider', queue_id: pause_queue.id, reason_code: 'synthetic_external'
    )
    get endpoint, headers: observer.create_new_auth_token
    expect(response.parsed_body.fetch('agents').sole.fetch('pause_notice')).to be_nil
  end

  context 'when the current pause belongs to Unit B' do
    let(:pause_queue) { queues.last }

    it 'returns no duration notice to a Unit A supervisor despite another authorized membership for the same operator' do
      get endpoint, headers: observer.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('agents').sole.fetch('pause_notice')).to be_nil
      expect(response.body).not_to include('SYNTHETIC PRIVATE pause duration explanation')
    end

    it 'keeps private text hidden when a Group supervisor can observe the current queue duration' do
      JrcCrm::UserBusinessUnit.find_by!(account: account, user: observer).update!(scope: 'GROUP', company: nil, business_unit: nil)
      travel_to(event.started_at + 61.seconds) do
        get endpoint, headers: observer.create_new_auth_token
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.fetch('agents').sole.dig('pause_notice', 'exceeded')).to be(true)
        expect(response.body).not_to include('SYNTHETIC PRIVATE pause duration explanation')
      end
    end
  end
end

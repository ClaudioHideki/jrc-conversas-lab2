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
  let(:native_pending) do
    call = JrcContactCenter::CallSession.create!(account: account, provider: 'jrc_pabx', correlation_id: SecureRandom.uuid,
                                                 direction: 'inbound', status: 'ended', started_at: 1.minute.ago, ended_at: Time.current,
                                                 current_unit: pause_queue.unit, current_queue: pause_queue)
    JrcContactCenter::Qualification.create!(account: account, account_user: member, call_session: call,
                                            channel: 'voice', started_at: Time.current, acw_limit_seconds: 60)
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
    Current.reset
  end

  it 'exposes only duration and an exceeded flag without resuming availability or exposing private definition/text' do
    previous = event.attributes.deep_dup
    travel_to(Time.zone.at((event.started_at + 61.seconds).to_f.ceil)) do
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
      travel_to(Time.zone.at((event.started_at + elapsed.seconds).to_f.ceil)) do
        get endpoint, headers: observer.create_new_auth_token
        expect(response.parsed_body.fetch('agents').sole.fetch('pause_notice')).to eq('elapsed_seconds' => elapsed, 'exceeded' => false)
      end
    end
  end

  it 'uses the immutable event limit rather than changing an existing pause when the catalog changes' do
    previous = event.attributes.deep_dup
    catalog.update!({ 'enforced' => true, 'entries' => [reason.merge('maximum_minutes' => 100)] }, expected_revision: catalog.revision)
    travel_to(Time.zone.at((event.started_at + 61.seconds).to_f.ceil)) do
      get endpoint, headers: observer.create_new_auth_token
      expect(response.parsed_body.fetch('agents').sole.dig('pause_notice', 'exceeded')).to be(true)
      expect(event.reload.attributes).to eq(previous)
    end
  end

  it 'does not derive a duration notice after the operator loses current operating eligibility' do
    JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member).update!(eligible: false)
    get endpoint, headers: observer.create_new_auth_token
    expect(response.parsed_body.fetch('agents').sole.fetch('pause_notice')).to be_nil
    expect(response.parsed_body.fetch('agents').sole.fetch('state_notice')).to be_nil
  end

  it 'does not derive a duration notice after the current queue membership is withdrawn' do
    JrcContactCenter::QueueMembership.find_by!(account: account, account_user: member, queue: pause_queue).update!(active: false)
    get endpoint, headers: observer.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('agents')).to be_empty
    JrcCrm::UserBusinessUnit.find_by!(account: account, user: observer).update!(scope: 'GROUP', company: nil, business_unit: nil)
    get endpoint, headers: observer.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('agents').sole.fetch('pause_notice')).to be_nil
    expect(response.parsed_body.fetch('agents').sole.fetch('state_notice')).to be_nil
    expect(response.body).not_to include('SYNTHETIC PRIVATE pause duration explanation')
  end

  it 'does not invent an informational limit for an external provider pause without a native local definition' do
    JrcContactCenter::AgentStateManager.new(account: account, account_user: member).record_provider_event(
      state: 'paused', occurred_at: event.started_at + 1.second, external_event_id: SecureRandom.uuid,
      provider: 'synthetic-provider', queue_id: pause_queue.id, reason_code: 'synthetic_external'
    )
    get endpoint, headers: observer.create_new_auth_token
    expect(response.parsed_body.fetch('agents').sole.fetch('pause_notice')).to be_nil
  end

  it 'observes a real elapsed legacy provider pause without inventing an informational limit' do
    current = JrcContactCenter::AgentStateManager.new(account: account, account_user: member).record_provider_event(
      state: 'paused', occurred_at: event.started_at + 1.second, external_event_id: SecureRandom.uuid,
      provider: 'synthetic-provider', queue_id: pause_queue.id, reason_code: 'synthetic_external'
    )
    previous = current.attributes.deep_dup
    travel_to(Time.zone.at((current.started_at + 61.seconds).to_f.ceil)) do
      get endpoint, headers: observer.create_new_auth_token
      data = response.parsed_body.fetch('agents').sole
      expect(data.fetch('state_notice')).to eq('state' => 'paused', 'state_version' => current.id.to_s, 'elapsed_seconds' => 61)
      expect(data.fetch('pause_notice')).to be_nil
      expect(current.reload.attributes).to eq(previous)
    end
  end

  it 'observes elapsed local availability without announcing confirmed PABX eligibility' do
    current = JrcContactCenter::AgentStateManager.new(account: account, account_user: member).transition(
      state: 'available', queue_id: pause_queue.id, command_id: SecureRandom.uuid, expected_state_version: event.id.to_s
    )
    travel_to(Time.zone.at((current.started_at + 61.seconds).to_f.ceil)) do
      get endpoint, headers: observer.create_new_auth_token
      data = response.parsed_body.fetch('agents').sole
      expect(data.fetch('state_notice')).to eq('state' => 'available', 'state_version' => current.id.to_s, 'elapsed_seconds' => 61)
      expect(data.values_at('eligible', 'provider_confirmed')).to eq([false, false])
    end
  end

  it 'keeps a real observed offline zero distinct from a missing state event' do
    current = JrcContactCenter::AgentStateManager.new(account: account, account_user: member).record_provider_event(
      state: 'offline', occurred_at: event.started_at + 1.second, external_event_id: SecureRandom.uuid,
      provider: 'synthetic-provider', queue_id: pause_queue.id
    )
    travel_to(Time.zone.at(current.started_at.to_f.ceil)) do
      get endpoint, headers: observer.create_new_auth_token
      data = response.parsed_body.fetch('agents').sole
      expect(data.fetch('state_notice')).to eq('state' => 'offline', 'state_version' => current.id.to_s, 'elapsed_seconds' => 0)
    end
  end

  it 'does not present an old pause timestamp as the duration of projected pending ACW' do
    native_pending
    get endpoint, headers: observer.create_new_auth_token
    data = response.parsed_body.fetch('agents').sole
    expect(data.fetch('state')).to eq('acw')
    expect(data.fetch('state_notice')).to be_nil
    expect(native_pending.reload.completed_at).to be_nil
    expect(JrcContactCenter::AgentStateSnapshot.new(account_user: member).current.id).to eq(event.id)
  end

  it 'does not invent zero seconds or an observation for a member with no native state event' do
    new_actor = create(:user, :contact_center_eligible, account: account, role: :agent)
    new_member = account.account_users.find_by!(user: new_actor)
    JrcContactCenter::QueueMembership.create!(account: account, queue: pause_queue, account_user: new_member)
    get endpoint, headers: observer.create_new_auth_token
    data = response.parsed_body.fetch('agents').find { |row| row.fetch('account_user_id') == new_member.id.to_s }
    expect(data).to include('state' => 'offline', 'state_version' => '0', 'state_notice' => nil)
    expect(JrcContactCenter::AgentStateEvent.where(account_user: new_member)).not_to exist
  end

  it 'does not count a supervision-only queue participant as an operational agent' do
    supervisor = create(:user, :contact_center_eligible, account: account, role: :agent)
    supervisor_member = account.account_users.find_by!(user: supervisor)
    link = JrcContactCenter::QueueMembership.create!(account: account, queue: pause_queue, account_user: supervisor_member, role: 'supervisor')
    get endpoint, headers: observer.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('agents').pluck('account_user_id')).to eq([member.id.to_s])
    expect(link.reload.role).to eq('supervisor')
  end

  context 'when the current pause belongs to Unit B' do
    let(:pause_queue) { queues.last }

    it 'returns no duration notice to a Unit A supervisor despite another authorized membership for the same operator' do
      get endpoint, headers: observer.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('agents').sole.fetch('pause_notice')).to be_nil
      expect(response.parsed_body.fetch('agents').sole.fetch('state_notice')).to be_nil
      expect(response.body).not_to include('SYNTHETIC PRIVATE pause duration explanation')
    end

    it 'keeps private text hidden when a Group supervisor can observe the current queue duration' do
      JrcCrm::UserBusinessUnit.find_by!(account: account, user: observer).update!(scope: 'GROUP', company: nil, business_unit: nil)
      travel_to(Time.zone.at((event.started_at + 61.seconds).to_f.ceil)) do
        get endpoint, headers: observer.create_new_auth_token
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.fetch('agents').sole.dig('pause_notice', 'exceeded')).to be(true)
        expect(response.body).not_to include('SYNTHETIC PRIVATE pause duration explanation')
      end
    end
  end

  context 'with an explicitly disabled time alert on the original local pause' do
    let(:reason) { super().merge('time_alert_enabled' => false) }

    it 'keeps factual elapsed time and the exceeded measurement without ending the pause or revealing private fields' do
      previous = event.attributes.deep_dup
      travel_to(Time.zone.at((event.started_at + 61.seconds).to_f.ceil)) do
        get endpoint, headers: observer.create_new_auth_token
        expect(response).to have_http_status(:ok)
        data = response.parsed_body.fetch('agents').sole
        expect(data.fetch('pause_notice')).to eq('elapsed_seconds' => 61, 'exceeded' => true, 'time_alert_enabled' => false)
        expect(data.fetch('state')).to eq('paused')
        expect(event.reload.attributes).to eq(previous)
        expect(member.reload.availability).to eq('busy')
        expect(data).not_to have_key('pause_definition')
      end
    end

    it 'retains the original disabled policy after a later catalog edit enables alerts for new pauses' do
      previous = event.attributes.deep_dup
      catalog.update!({ 'enforced' => true, 'entries' => [reason.merge('time_alert_enabled' => true)] }, expected_revision: catalog.revision)
      travel_to(Time.zone.at((event.started_at + 61.seconds).to_f.ceil)) do
        get endpoint, headers: observer.create_new_auth_token
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.fetch('agents').sole.dig('pause_notice', 'time_alert_enabled')).to be(false)
        expect(event.reload.attributes).to eq(previous)
        expect(catalog.call.fetch('entries').sole.fetch('time_alert_enabled')).to be(true)
      end
    end
  end

  context 'with an explicitly enabled time alert' do
    let(:reason) { super().merge('time_alert_enabled' => true) }

    it 'reports the observed threshold and enabled flag while preserving the paused state' do
      travel_to(Time.zone.at((event.started_at + 61.seconds).to_f.ceil)) do
        get endpoint, headers: observer.create_new_auth_token
        expect(response).to have_http_status(:ok)
        data = response.parsed_body.fetch('agents').sole
        expect(data.fetch('pause_notice')).to eq('elapsed_seconds' => 61, 'exceeded' => true, 'time_alert_enabled' => true)
        expect(data.fetch('state')).to eq('paused')
      end
    end
  end
end

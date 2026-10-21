# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcContactCenter::QualificationManager do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: agent) }
  let(:manager) { described_class.new(account: account, member: member) }
  let(:session) do
    JrcContactCenter::CallSession.create!(account: account, provider: 'jrc_pabx', correlation_id: 'acw-call',
                                         direction: 'inbound', status: 'connected', started_at: 2.minutes.ago, answered_at: 1.minute.ago)
  end
  let!(:leg) do
    JrcContactCenter::CallLeg.create!(account: account, call_session: session, account_user: member,
                                     direction: 'inbound', status: 'connected', started_at: session.started_at, answered_at: session.answered_at)
  end
  let(:whatsapp) { create(:channel_whatsapp, account: account, phone_number: "+5599#{SecureRandom.random_number(10**9).to_s.rjust(9, '0')}") }
  let(:inbox) { create(:inbox, account: account, channel: whatsapp) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: agent) }

  before do
    account.enable_features!('jrc_contact_center')
    stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook').to_return(status: 200, body: '{}')
    stub_request(:get, 'https://waba.360dialog.io/v1/configs/templates').to_return(status: 200, body: '{"waba_templates":[]}', headers: { 'Content-Type' => 'application/json' })
  end

  it 'does not enter ACW when hangup is requested without terminal confirmation' do
    expect { manager.start!(call_session: session) }.to raise_error(JrcContactCenter::OperationError, 'call_not_ended')
    expect(JrcContactCenter::Qualification.where(account: account)).to be_empty
  end

  it 'persists one pending qualification on confirmed voice termination and restores it on replay' do
    session.update!(status: 'ended', ended_at: Time.current)
    qualification = JrcContactCenter::Qualification.find_by!(call_session: session, account_user: member)
    expect(qualification).to have_attributes(channel: 'voice', completed_at: nil, acw_limit_seconds: 180)
    expect(manager.start!(call_session: session).id).to eq(qualification.id)
    expect(JrcContactCenter::Qualification.where(call_session: session).count).to eq(1)
    expect(JrcContactCenter::AgentStateSnapshot.new(account_user: member).call).to include(state: 'acw', eligible: false,
                                                                                         eligibility_reason: 'tabulation_pending', provider_confirmed: false)
  end

  it 'creates required tabulation for a confirmed terminal agent leg even when the transferred call continues' do
    leg.update!(status: 'transferred', ended_at: Time.current)
    expect(JrcContactCenter::Qualification.pending.find_by!(call_session: session).account_user_id).to eq(member.id)
    expect(session.reload.status).to eq('connected')
  end

  it 'handles remote/provider termination through the existing verified event inbox' do
    event = JrcContactCenter::EventIngestor.new(account: account).call(
      { schema_version: '1.0', event_id: 'acw-remote-end', event_type: 'call.ended', occurred_at: Time.current.iso8601,
        provider: 'jrc_pabx', correlation_id: session.correlation_id }, signature_verified: true
    ).record
    JrcContactCenter::EventReconciler.new(event_record: event).call
    expect(event.reload.status).to eq('processed')
    expect(session.reload.status).to eq('ended')
    expect(JrcContactCenter::Qualification.pending.where(call_session: session, account_user: member).count).to eq(1)
    JrcContactCenter::EventReconciler.new(event_record: event).call
    expect(JrcContactCenter::Qualification.where(call_session: session).count).to eq(1)
  end

  it 'repairs a terminal reload without creating a duplicate qualification' do
    session.update_columns(status: 'ended', ended_at: Time.current)
    described_class.ensure_voice!(session.reload)
    described_class.ensure_voice!(session.reload)
    expect(JrcContactCenter::Qualification.pending.where(call_session: session).count).to eq(1)
  end

  it 'requires reason and result, retaining the persisted pending obligation on failure' do
    record = manager.start!(conversation: conversation)
    expect { manager.complete!(record, { reason_code: 'order', outcome_code: '' }) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(record.reload.completed_at).to be_nil
    expect(conversation.reload.status).to eq('open')
  end

  it 'resolves WhatsApp only after persisted tabulation and is idempotent on double submit' do
    record = manager.start!(conversation: conversation)
    expect(conversation.reload.status).to eq('open')
    result = manager.complete!(record, { reason_code: 'order', outcome_code: 'completed', notes: 'Persisted operational note' })
    replay = manager.complete!(record, { reason_code: 'transfer', outcome_code: 'forwarded' })
    expect(result.reload).to have_attributes(reason_code: 'order', outcome_code: 'completed', notes: 'Persisted operational note')
    expect(result.completed_at).to be_present
    expect(replay.id).to eq(record.id)
    expect(JrcContactCenter::Qualification.where(conversation: conversation).count).to eq(1)
    expect(conversation.reload.status).to eq('resolved')
  end

  it 'blocks direct native conversation resolution before tabulation' do
    expect { conversation.update!(status: :resolved) }.to raise_error(ActiveRecord::RecordInvalid, /contact_center_tabulation_required/)
    expect(conversation.reload.status).to eq('open')
  end

  it 'does not impose tabulation on email, social or API/widget conversations' do
    other = create(:conversation, account: account)
    expect { other.update!(status: :resolved) }.not_to raise_error
    expect { manager.start!(conversation: other) }.to raise_error(JrcContactCenter::OperationError, 'attendance_not_owned')
  end

  it 'preserves mandatory ACW after the configured limit and persists overdue/exceeded values' do
    JrcContactCenter::AcwPolicy.new(account: account).update!(voice: 2, whatsapp: 2)
    record = manager.start!(conversation: conversation)
    travel_to(record.started_at + 4.seconds, with_usec: true) do
      record.refresh_overdue!
      expect(record.reload).to have_attributes(overdue: true, completed_at: nil, exceeded_seconds: 2)
      expect(JrcContactCenter::AgentStateSnapshot.new(account_user: member).call[:eligible]).to be(false)
      manager.complete!(record, { reason_code: 'information', outcome_code: 'completed' })
      expect(record.reload).to have_attributes(duration_seconds: 4, overdue: true, exceeded_seconds: 2)
    end
  end

  it 'does not accept an operator Available command during pending tabulation' do
    record = manager.start!(conversation: conversation)
    snapshot = JrcContactCenter::AgentStateSnapshot.new(account_user: member)
    expect do
      JrcContactCenter::AgentStateManager.new(account: account, account_user: member)
                                       .transition(state: 'available', command_id: 'skip-acw', expected_state_version: snapshot.version)
    end.to raise_error(JrcContactCenter::OperationError, 'tabulation_pending')
    expect(record.reload.completed_at).to be_nil
  end

  it 'does not become eligible after a late provider Available event while pending' do
    manager.start!(conversation: conversation)
    JrcContactCenter::AgentStateManager.new(account: account, account_user: member)
                                     .record_provider_event(state: 'available', occurred_at: 1.second.from_now,
                                                            external_event_id: 'late-available', provider: 'jrc_pabx')
    expect(JrcContactCenter::AgentStateSnapshot.new(account_user: member).call).to include(state: 'acw', eligible: false, provider_confirmed: false)
  end

  it 'releases the operational agent state after completed voice ACW without claiming PABX confirmation' do
    session.update!(status: 'ended', ended_at: Time.current)
    record = JrcContactCenter::Qualification.find_by!(call_session: session)
    manager.complete!(record, { reason_code: 'order', outcome_code: 'completed' })
    expect(JrcContactCenter::AgentStateSnapshot.new(account_user: member).call).to include(state: 'available', provider_confirmed: false)
    expect(record.reload.operational_payload).to include('reason_code' => 'order', 'agent_name' => agent.available_name)
    expect(JrcContactCenter::AgentStateEvent.where(account: account, state: 'acw', ended_at: nil)).to be_empty
  end

  it 'does not use another account member or attendance' do
    foreign = create(:account)
    expect { described_class.new(account: foreign, member: member) }.to raise_error(ActiveRecord::RecordNotFound)
    other = create(:conversation)
    expect { manager.start!(conversation: other) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'does not allow another agent to complete the pending qualification' do
    other = create(:user, account: account, role: :agent)
    other_member = account.account_users.find_by!(user: other)
    record = manager.start!(conversation: conversation)
    expect do
      described_class.new(account: account, member: other_member).complete!(record, { reason_code: 'order', outcome_code: 'completed' })
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'does not assign another conversation to an agent while ACW is pending' do
    manager.start!(conversation: conversation)
    next_conversation = create(:conversation, account: account, inbox: inbox)
    expect { next_conversation.update!(assignee: agent) }.to raise_error(ActiveRecord::RecordInvalid, /contact_center_agent_acw/)
  end

  it 'excludes pending ACW from the native round robin and restores that pool only after completion' do
    create(:inbox_member, inbox: inbox, user: agent)
    record = manager.start!(conversation: conversation)
    selector = AutoAssignment::InboxRoundRobinService.new(inbox: inbox)
    expect(selector.available_agent(allowed_agent_ids: [agent.id.to_s])).to be_nil
    manager.complete!(record, { reason_code: 'order', outcome_code: 'completed' })
    expect(selector.available_agent(allowed_agent_ids: [agent.id.to_s]).id).to eq(agent.id)
  end

  it 'rejects a new originate command before recording or dispatching during ACW' do
    manager.start!(conversation: conversation)
    adapter = instance_double(JrcContactCenter::Providers::JrcPabxAdapter)
    expect(adapter).not_to receive(:dispatch)
    expect do
      JrcContactCenter::CommandDispatcher.new(account: account, actor_account_user: member, adapter: adapter)
                                       .call(action: 'originate', parameters: { destination: '1001' })
    end.to raise_error(JrcContactCenter::OperationError, 'tabulation_pending')
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  it 'starts a new cycle after a completed WhatsApp conversation is reopened' do
    first = manager.start!(conversation: conversation)
    manager.complete!(first, { reason_code: 'order', outcome_code: 'completed' })
    conversation.reload.update!(status: :open)
    second = manager.start!(conversation: conversation)
    expect(second.id).not_to eq(first.id)
    expect(second.conversation_cycle).to eq(1)
    expect { conversation.update!(status: :resolved) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(JrcContactCenter::Qualification.where(conversation: conversation).count).to eq(2)
  end

  it 'does not allow a direct attribute update to reuse an old completed cycle' do
    first = manager.start!(conversation: conversation)
    manager.complete!(first, { reason_code: 'order', outcome_code: 'completed' })
    conversation.reload.update!(status: :open)
    expect do
      conversation.update!(additional_attributes: conversation.additional_attributes.merge('jrc_acw_cycle' => 0), status: :resolved)
    end.to raise_error(ActiveRecord::RecordInvalid, /contact_center_cycle_is_readonly/)
    expect(conversation.reload.status).to eq('open')
  end
end

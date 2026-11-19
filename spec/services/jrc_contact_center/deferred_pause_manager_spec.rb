require 'rails_helper'

RSpec.describe JrcContactCenter::DeferredPauseManager do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:manager) { described_class.new(account: account, member: member) }
  let(:state_manager) { JrcContactCenter::AgentStateManager.new(account: account, account_user: member) }
  let(:snapshot) { JrcContactCenter::AgentStateSnapshot.new(account_user: member) }
  let(:values) do
    { command_id: SecureRandom.uuid, expected_state_version: snapshot.version, reason_code: 'lunch',
      expected_request_revision: JrcContactCenter::DeferredPauseRevision.token(account: account, member: member) }
  end
  let(:call) do
    JrcContactCenter::CallSession.create!(account: account, provider: 'jrc_pabx', correlation_id: SecureRandom.uuid,
                                          direction: 'inbound', status: 'connected', started_at: 2.minutes.ago, answered_at: 1.minute.ago)
  end
  let(:qualification) do
    call.update!(status: 'ended', ended_at: Time.current)
    JrcContactCenter::Qualification.pending.find_by!(call_session: call, account_user: member)
  end
  let(:completion) { JrcContactCenter::QualificationManager.new(account: account, member: member) }
  let(:answers) { { reason_code: 'order', outcome_code: 'completed', notes: 'SYNTHETIC private ACW draft' } }
  let(:pauses) { JrcContactCenter::AgentStateEvent.where(account: account, account_user: member, state: 'paused') }

  before do
    account.enable_features!('jrc_contact_center')
    JrcContactCenter::CallLeg.create!(account: account, call_session: call, account_user: member, direction: 'inbound',
                                      status: 'connected', started_at: call.started_at, answered_at: call.answered_at)
    state_manager.record_provider_event(state: 'available', occurred_at: Time.current, external_event_id: SecureRandom.uuid,
                                        provider: 'jrc_conversas', derived: true)
  end

  it 'persists the request without altering the live call, native availability or current state' do
    previous = member.reload.availability
    request = manager.request!(values)
    expect(request.reload.state).to eq('pending')
    expect(call.reload.status).to eq('connected')
    expect(call.legs.sole.status).to eq('connected')
    expect(member.reload.availability).to eq(previous)
    expect(pauses).to be_empty
    expect(JrcContactCenter::DeferredPauseRequest.active.where(account: account, account_user: member).count).to eq(1)
  end

  it 'keeps the request waiting through the real call closure and overdue ACW without discarding the draft' do
    request = manager.request!(values)
    qualification.update!(notes: 'SYNTHETIC preserved private draft')
    travel_to(qualification.started_at + qualification.acw_limit_seconds.seconds + 5.seconds) do
      qualification.operational_payload
      manager.apply_pending!
      expect(qualification.reload).to have_attributes(completed_at: nil, notes: 'SYNTHETIC preserved private draft', overdue: true)
      expect(request.reload.state).to eq('pending')
      expect(pauses).to be_empty
      expect(snapshot.call[:eligible]).to be(false)
    end
  end

  it 'starts one native pause only after call end and ACW completion and preserves its local-only identity' do
    request = manager.request!(values)
    travel 3.minutes do
      completion.complete!(qualification, answers)
      expect(request.reload.state).to eq('applied')
      expect(pauses.count).to eq(1)
      expect(pauses.sole.started_at).to be >= qualification.reload.completed_at
      expect(pauses.sole.started_at).to be > request.created_at
      expect(pauses.sole.metadata.fetch('provider_confirmed')).to be(false)
      expect(member.reload.availability).to eq('lunch_break')
      expect(JrcContactCenter::AgentStateSnapshot.new(account_user: member).call[:eligible]).to be(false)
    end
  end

  it 'does not duplicate a request or pause when request, completion and the callback are repeated' do
    request = manager.request!(values)
    completion.complete!(qualification, answers)
    completion.complete!(qualification, answers)
    manager.apply_pending!
    expect(manager.request!(values).id).to eq(request.id)
    expect(JrcContactCenter::DeferredPauseRequest.where(account: account).count).to eq(1)
    expect(pauses.count).to eq(1)
    expect(request.reload.finished_at).to be_present
  end

  it 'rejects UUID reuse with different body and preserves the first request' do
    request = manager.request!(values)
    expect { manager.request!(values.merge(reason_code: 'coffee')) }.to raise_error(JrcContactCenter::OperationError, 'command_id_conflict')
    expect(request.reload.reason_code).to eq('lunch')
    expect(pauses).to be_empty
  end

  it 'rejects another active request rather than replacing the pending reason silently' do
    request = manager.request!(values)
    expect do
      manager.request!(values.merge(command_id: SecureRandom.uuid, reason_code: 'coffee'))
    end.to raise_error(JrcContactCenter::OperationError, 'pause_request_exists')
    expect(request.reload.reason_code).to eq('lunch')
  end

  it 'does not create an unrelated future pause after the call and ACW have already completed' do
    completion.complete!(qualification, answers)
    version = JrcContactCenter::AgentStateSnapshot.new(account_user: member).version
    expect do
      manager.request!(values.merge(expected_state_version: version))
    end.to raise_error(JrcContactCenter::OperationError, 'deferred_pause_not_needed')
    expect(JrcContactCenter::DeferredPauseRequest.where(account: account)).to be_empty
    expect(pauses).to be_empty
  end

  %w[available paused offline].each do |state|
    it "does not silently replace the pending intent with a manual #{state} transition or a forged internal command ID" do
      request = manager.request!(values)
      expect do
        state_manager.transition(
          state: state, reason_code: 'lunch', command_id: "deferred-pause:#{request.request_id}",
          expected_state_version: JrcContactCenter::AgentStateSnapshot.new(account_user: member).version
        )
      end.to raise_error(JrcContactCenter::OperationError, 'pause_request_exists')
      expect(request.reload.state).to eq('pending')
      expect(pauses).to be_empty
    end
  end

  it 'allows explicit idempotent withdrawal and never starts the cancelled pause later' do
    request = manager.request!(values)
    manager.cancel!(request.request_id)
    manager.cancel!(request.request_id)
    completion.complete!(qualification, answers)
    expect(request.reload.state).to eq('cancelled')
    expect(request.finished_at).to be_present
    expect(pauses).to be_empty
    expect(Audited::Audit.where(auditable: request, comment: JrcContactCenter::DeferredPauseAudit::COMMENT).count).to eq(2)
  end

  it 'does not use cancellation to end an already applied native pause' do
    request = manager.request!(values)
    completion.complete!(qualification, answers)
    expect { manager.cancel!(request.request_id) }.to raise_error(JrcContactCenter::OperationError, 'pause_already_applied')
    expect(pauses.sole.ended_at).to be_nil
    expect(member.reload.availability).to eq('lunch_break')
  end

  it 'rejects a delayed different UUID after withdrawal even though the historical state version has not changed' do
    before_version = snapshot.version
    request = manager.request!(values)
    manager.cancel!(request.request_id)
    expect(JrcContactCenter::AgentStateSnapshot.new(account_user: member).version).to eq(before_version)
    expect do
      manager.request!(values.merge(command_id: SecureRandom.uuid))
    end.to raise_error(JrcContactCenter::OperationError, 'stale_pause_request')
    expect(manager.request!(values)).to have_attributes(id: request.id, state: 'cancelled')
    expect(JrcContactCenter::DeferredPauseRequest.where(account: account).count).to eq(1)
    expect(pauses).to be_empty
  end

  it 'requires a fresh request revision for a separately reviewed request after withdrawal' do
    request = manager.request!(values)
    manager.cancel!(request.request_id)
    revised = JrcContactCenter::DeferredPauseRevision.token(account: account, member: member)
    expect(revised).not_to eq(values[:expected_request_revision])
    replacement = manager.request!(values.merge(command_id: SecureRandom.uuid, expected_request_revision: revised))
    expect(replacement).to have_attributes(state: 'pending', reason_code: 'lunch')
    expect(request.reload.state).to eq('cancelled')
    expect(JrcContactCenter::DeferredPauseRequest.active.where(account: account).pluck(:id)).to eq([replacement.id])
    expect(pauses).to be_empty
  end

  it 'does not invalidate the request revision merely because ACW time or private draft answers change' do
    request = manager.request!(values)
    revision = JrcContactCenter::DeferredPauseRevision.token(account: account, member: member)
    qualification.update!(notes: 'SYNTHETIC changed private draft')
    travel 3.minutes do
      qualification.operational_payload
      expect(JrcContactCenter::DeferredPauseRevision.token(account: account, member: member)).to eq(revision)
      expect(request.reload.state).to eq('pending')
    end
  end

  it 'blocks a pending request when the catalogue changes rather than applying a changed policy' do
    request = manager.request!(values)
    account.update!(settings: account.settings.merge(JrcContactCenter::PauseCatalog::KEY => { 'version' => 1, 'enforced' => false, 'entries' => [] }))
    completion.complete!(qualification, answers)
    expect(request.reload).to have_attributes(state: 'blocked', failure_code: 'pause_catalog_changed', finished_at: nil)
    expect(pauses).to be_empty
    expect(JrcContactCenter::AgentStateSnapshot.new(account_user: member).call[:eligibility_reason]).to eq('pause_pending')
  end

  it 'revalidates eligibility before applying and requires a separate explicit review after revocation' do
    request = manager.request!(values)
    JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member).update!(eligible: false)
    manager.apply_pending!
    expect(request.reload).to have_attributes(state: 'blocked', failure_code: 'access_revoked')
    expect(pauses).to be_empty
    expect { manager.cancel!(request.request_id) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'keeps justification, labels and reason bodies out of the audit trail and supervisor payload' do
    request = manager.request!(values)
    audit = Audited::Audit.find_by!(auditable: request, comment: JrcContactCenter::DeferredPauseAudit::COMMENT)
    expect(audit.audited_changes).not_to have_key('justification')
    expect(audit.audited_changes).not_to have_key('reason_label')
    expect(snapshot.call).not_to have_key(:deferred_pause_request)
    expect(snapshot.operator_payload.fetch(:deferred_pause_request)).to include('request_id' => request.request_id)
    expect(request.actor_user_id).to eq(actor.id)
  end
end

require 'rails_helper'

RSpec.describe JrcContactCenter::QualificationDraft do
  include ActiveSupport::Testing::TimeHelpers

  let(:account) { create(:account, name: 'SYNTHETIC pending ACW') }
  let(:agent) { create(:user, :contact_center_eligible, account: account) }
  let(:member) { account.account_users.find_by!(user: agent) }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, code: 'DRAFT', name: 'SYNTHETIC draft unit', kind: 'sac') }
  let(:queue) { JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'DRAFT', name: 'SYNTHETIC draft queue') }
  let(:session) do
    JrcContactCenter::CallSession.create!(account: account, provider: 'jrc_pabx', correlation_id: SecureRandom.uuid,
                                          direction: 'inbound', status: 'connected', current_queue_id: queue.id,
                                          started_at: 3.minutes.ago, answered_at: 2.minutes.ago)
  end
  let(:leg) do
    JrcContactCenter::CallLeg.create!(account: account, call_session: session, account_user: member, queue: queue,
                                      direction: 'inbound', status: 'connected', started_at: session.started_at, answered_at: session.answered_at)
  end
  let(:record) do
    session.update!(status: 'ended', ended_at: Time.current)
    JrcContactCenter::Qualification.find_by!(account: account, account_user: member, call_session: session)
  end
  let(:event) { JrcContactCenter::AgentStateEvent.find_by!(account: account, external_event_id: "qualification:#{record.id}:pending") }
  let(:service) { described_class.new(account: account, member: member) }
  let(:revision) { JrcContactCenter::QualificationDraftRevision.token(record) }
  let(:audits) { Audited.audit_class.where(auditable: record, comment: described_class::AUDIT_COMMENT) }

  before do
    account.enable_features!('jrc_contact_center')
    leg
  end

  around { |example| freeze_time { example.run } }

  it 'persists incomplete manual answers without completing attendance, resetting its clock or changing native state events' do
    started = record.started_at
    events = JrcContactCenter::AgentStateEvent.where(account: account).pluck(:id, :state, :ended_at, :metadata)
    service.save!(record, { reason_code: 'order', notes: 'SYNTHETIC unfinished answers' }, expected_revision: revision)
    expect(record.reload).to have_attributes(reason_code: 'order', notes: 'SYNTHETIC unfinished answers', outcome_code: nil,
                                              completed_at: nil, duration_seconds: nil, started_at: started)
    expect(JrcContactCenter::AgentStateEvent.where(account: account).pluck(:id, :state, :ended_at, :metadata)).to eq(events)
    expect(audits.count).to eq(1)
    expect(audits.sole.audited_changes.to_json).not_to include('SYNTHETIC unfinished answers')
    expect(JrcContactCenter::AgentStateSnapshot.new(account_user: member).call.fetch(:eligible)).to be(false)
    expect(JrcContactCenter::CallFactContribution.new(session: session).call.fetch('measurements').fetch('acw_completed_count')).to eq(0)
  end

  it 'keeps the manual-state revision stable across an overdue clock observation' do
    original = revision
    travel 4.minutes
    record.operational_payload
    expect(record.reload).to be_overdue
    expect(JrcContactCenter::QualificationDraftRevision.token(record)).to eq(original)
    service.save!(record, { notes: 'SYNTHETIC saved after a clock poll' }, expected_revision: original)
    expect(record.reload.notes).to eq('SYNTHETIC saved after a clock poll')
    expect(record.completed_at).to be_nil
  end

  it 'keeps manual answers out of shared agent and supervisor state while preserving the pending blocker' do
    service.save!(record, { reason_code: 'order', outcome_code: 'pending', notes: 'SYNTHETIC private answer' }, expected_revision: revision)
    snapshot = JrcContactCenter::AgentStateSnapshot.new(account_user: member)
    state = snapshot.call
    expect(state).to include(eligible: false, eligibility_reason: 'tabulation_pending', state: 'acw')
    expect(state.fetch(:pending_qualifications).sole).to include('id' => record.id, 'notes' => nil, 'reason_code' => nil, 'outcome_code' => nil)
    expect(snapshot.operator_payload.to_json).not_to include('SYNTHETIC private answer')
    expect(record.reload).to have_attributes(reason_code: 'order', outcome_code: 'pending', notes: 'SYNTHETIC private answer')
  end

  it 'uses queue before team before general from the captured snapshot without rewriting that snapshot' do
    team = create(:team, account: account)
    team.add_members([agent.id])
    policy = JrcContactCenter::AcwPolicy.new(account: account)
    general = { id: 'general', reason_code: 'order', scope: 'general', scope_id: nil, active: true, limit_seconds: 180 }
    rules = [general, general.merge(id: 'team', scope: 'team', scope_id: team.id, limit_seconds: 120),
             general.merge(id: 'queue', scope: 'queue', scope_id: queue.id, limit_seconds: 60)]
    policy.update!({ voice: 180, whatsapp: 180 }, voice_rules: rules, expected_revision: policy.revision)
    snapshot = event.metadata.deep_dup
    policy.update!({ voice: 300, whatsapp: 240 }, voice_rules: [], expected_revision: policy.revision)
    team.remove_members([agent.id])
    travel 90.seconds
    service.save!(record, { reason_code: 'order' }, expected_revision: revision)
    expect(record.reload).to have_attributes(acw_limit_seconds: 60, overdue: true, exceeded_seconds: 30, completed_at: nil)
    expect(event.reload.metadata).to eq(snapshot)
    expect(event.ended_at).to be_nil
  end

  it 'returns to the captured default for another reason rather than using the selected reason limit as a new default' do
    policy = JrcContactCenter::AcwPolicy.new(account: account)
    values = [{ id: 'queue', reason_code: 'order', scope: 'queue', scope_id: queue.id, active: true, limit_seconds: 60 }]
    policy.update!({ voice: 180, whatsapp: 180 }, voice_rules: values, expected_revision: policy.revision)
    saved = service.save!(record, { reason_code: 'order' }, expected_revision: revision)
    expect(saved.acw_limit_seconds).to eq(60)
    saved = service.save!(saved, { reason_code: 'information' }, expected_revision: JrcContactCenter::QualificationDraftRevision.token(saved))
    expect(saved).to have_attributes(acw_limit_seconds: 180, completed_at: nil)
    expect(event.ended_at).to be_nil
  end

  it 'keeps an old attendance on its captured global limit when scoped rules were introduced only later' do
    snapshot = event.metadata.deep_dup
    policy = JrcContactCenter::AcwPolicy.new(account: account)
    values = [{ id: 'new', reason_code: 'order', scope: 'queue', scope_id: queue.id, active: true, limit_seconds: 60 }]
    policy.update!({ voice: 300, whatsapp: 240 }, voice_rules: values, expected_revision: policy.revision)
    service.save!(record, { reason_code: 'order' }, expected_revision: revision)
    expect(record.reload.acw_limit_seconds).to eq(180)
    expect(event.reload.metadata).to eq(snapshot)
  end

  it 'saves incomplete answers without a reason using the captured default instead of weakening completion validation' do
    policy = JrcContactCenter::AcwPolicy.new(account: account)
    values = [{ id: 'queue', reason_code: 'order', scope: 'queue', scope_id: queue.id, active: true, limit_seconds: 60 }]
    policy.update!({ voice: 180, whatsapp: 180 }, voice_rules: values, expected_revision: policy.revision)
    saved = service.save!(record, { reason_code: 'order' }, expected_revision: revision)
    snapshot = event.metadata.deep_dup
    saved = service.save!(saved, { reason_code: '', notes: 'SYNTHETIC answers still incomplete' },
                         expected_revision: JrcContactCenter::QualificationDraftRevision.token(saved))
    expect(saved).to have_attributes(reason_code: '', acw_limit_seconds: 180, completed_at: nil)
    expect(event.reload.metadata).to eq(snapshot)
    manager = JrcContactCenter::QualificationManager.new(account: account, member: member)
    expect { manager.complete!(saved, reason_code: '', outcome_code: 'completed') }.to raise_error(JrcContactCenter::OperationError)
    expect(saved.reload.completed_at).to be_nil
  end

  it 'blocks same-level team conflicts before changing answers, clock or audit' do
    teams = Array.new(2) { create(:team, account: account) }
    teams.each { |team| team.add_members([agent.id]) }
    policy = JrcContactCenter::AcwPolicy.new(account: account)
    values = teams.map do |team|
      { id: "team-#{team.id}", reason_code: 'order', scope: 'team', scope_id: team.id, active: true, limit_seconds: 60 }
    end
    leg.update!(queue: nil)
    policy.update!({ voice: 180, whatsapp: 180 }, voice_rules: values, expected_revision: policy.revision)
    original = record.attributes
    expect { service.save!(record, { reason_code: 'order' }, expected_revision: revision) }
      .to raise_error(JrcContactCenter::AcwRulePrecedence::Conflict)
    expect(record.reload.attributes).to eq(original)
    expect(audits).to be_empty
    expect(event.ended_at).to be_nil
  end

  it 'rejects an old manual revision instead of replacing newer answers' do
    previous = revision
    service.save!(record, { notes: 'SYNTHETIC newer manual answer' }, expected_revision: previous)
    original = record.reload.attributes
    expect { service.save!(record, { notes: 'SYNTHETIC stale answer' }, expected_revision: previous) }
      .to raise_error(JrcContactCenter::OperationError, 'stale_configuration_revision')
    expect(record.reload.attributes).to eq(original)
    expect(audits.count).to eq(1)
  end

  it 'requires a revision even for an incomplete pending draft' do
    expect { service.save!(record, { notes: 'SYNTHETIC missing revision' }, expected_revision: nil) }
      .to raise_error(JrcContactCenter::OperationError, 'configuration_revision_required')
    expect(record.reload.notes).to be_nil
    expect(audits).to be_empty
  end

  it 'treats a duplicate save as idempotent and does not create another manual-change audit' do
    saved = service.save!(record, { reason_code: 'order', notes: 'SYNTHETIC same answer' }, expected_revision: revision)
    token = JrcContactCenter::QualificationDraftRevision.token(saved)
    travel 2.minutes
    service.save!(record, { reason_code: 'order', notes: 'SYNTHETIC same answer' }, expected_revision: token)
    expect(JrcContactCenter::QualificationDraftRevision.token(record.reload)).to eq(token)
    expect(audits.count).to eq(1)
    expect(record.completed_at).to be_nil
  end

  it 'does not allow a late draft to alter a completed native result' do
    previous = revision
    JrcContactCenter::QualificationManager.new(account: account, member: member)
                                        .complete!(record, reason_code: 'order', outcome_code: 'completed', notes: 'SYNTHETIC final answer')
    completed = record.reload.attributes
    expect { service.save!(record, { notes: 'SYNTHETIC late draft' }, expected_revision: previous) }
      .to raise_error(JrcContactCenter::OperationError, 'qualification_already_completed')
    expect(record.reload.attributes).to eq(completed)
    expect(audits).to be_empty
  end

  it 'rolls back manual answers when the mandatory sanitized audit fails' do
    original = record.attributes
    allow(Audited.audit_class).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(record))
    expect { service.save!(record, { notes: 'SYNTHETIC should roll back' }, expected_revision: revision) }
      .to raise_error(ActiveRecord::RecordInvalid)
    expect(record.reload.attributes).to eq(original)
    expect(audits).to be_empty
  end

  it 'does not accept a foreign account qualification with a valid-looking revision' do
    other = create(:user, :contact_center_eligible, account: create(:account))
    another = other.account_users.first
    foreign = described_class.new(account: another.account, member: another)
    expect { foreign.save!(record, { notes: 'SYNTHETIC foreign overwrite' }, expected_revision: revision) }
      .to raise_error(ActiveRecord::RecordNotFound)
    expect(record.reload.notes).to be_nil
  end

  it 'does not save a draft for another native account membership' do
    other = create(:user, :contact_center_eligible, account: account)
    another = account.account_users.find_by!(user: other)
    foreign = described_class.new(account: account, member: another)
    expect { foreign.save!(record, { notes: 'SYNTHETIC another operator' }, expected_revision: revision) }
      .to raise_error(ActiveRecord::RecordNotFound)
    expect(record.reload.notes).to be_nil
  end

  it 'rejects overlong codes and notes while preserving the pending record' do
    original = record.attributes
    expect { service.save!(record, { reason_code: 'x' * 101 }, expected_revision: revision) }
      .to raise_error(JrcContactCenter::OperationError, 'invalid_qualification_draft')
    expect { service.save!(record, { outcome_code: 'x' * 101 }, expected_revision: revision) }
      .to raise_error(JrcContactCenter::OperationError, 'invalid_qualification_draft')
    expect { service.save!(record, { notes: 'x' * 4001 }, expected_revision: revision) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(record.reload.attributes).to eq(original)
    expect(audits).to be_empty
  end

  it 'does not invent a start time for historical records without an ACW clock' do
    record.update!(started_at: nil)
    expect { service.save!(record, { notes: 'SYNTHETIC missing start' }, expected_revision: revision) }
      .to raise_error(JrcContactCenter::OperationError, 'qualification_not_started')
    expect(record.reload).to have_attributes(started_at: nil, notes: nil)
    expect(audits).to be_empty
  end
end

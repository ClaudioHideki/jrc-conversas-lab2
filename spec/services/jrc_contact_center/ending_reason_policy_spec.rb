require 'rails_helper'

RSpec.describe JrcContactCenter::EndingReasonPolicy do
  include_context 'with a frozen ending reason catalogue'

  it 'requires registered tabulation for the selected queue even while the old global voice option is false' do
    expect(policy.voice_required?).to be(false)
    expect(record).to be_persisted
    context = described_class.new(record).private_payload.fetch('ending_reason_context')
    expect(context).to include('required' => true, 'revision' => 1, 'options' => [entry.slice('code', 'name')])
    expect(context.keys.sort).to eq(%w[integrity_sha256 options required revision])
    expect(record.completed_at).to be_nil
  end

  it 'leaves a call started before activation on the legacy optional path instead of applying the new requirement retroactively' do
    old = JrcContactCenter::CallSession.create!(account: account, provider: 'synthetic', correlation_id: SecureRandom.uuid,
                                                direction: 'inbound', status: 'connected', started_at: 1.day.ago, current_queue: queue)
    JrcContactCenter::CallLeg.create!(account: account, call_session: old, account_user: member, queue: queue, direction: 'inbound',
                                      status: 'connected', started_at: old.started_at, answered_at: old.started_at)
    old.update!(status: 'ended', ended_at: Time.current)
    expect(old.reload.ending_reason_version_id).to be_nil
    expect(JrcContactCenter::Qualification.where(call_session: old)).to be_empty
  end

  it 'does not attach the new requirement retroactively to an old unpinned call through SQL' do
    old = JrcContactCenter::CallSession.create!(account: account, provider: 'synthetic', correlation_id: SecureRandom.uuid,
                                                direction: 'inbound', status: 'created', started_at: 1.day.ago)
    version = JrcContactCenter::EndingReasonVersion.where(account: account).sole
    expect do
      old.class.transaction(requires_new: true) do
        old.class.connection.execute("UPDATE #{old.class.table_name} SET ending_reason_version_id = #{version.id} WHERE id = #{old.id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /Call ending reason origin is immutable/)
    expect(old.reload.ending_reason_version_id).to be_nil
  end

  it 'preserves the call start version across a later catalogue change before ACW starts' do
    leg
    original = session.reload.ending_reason_version_id
    configure_ending_reasons!(entries: [entry.merge('name' => 'SYNTHETIC next', 'active' => false)], queues: [])
    expect(record.call_session.reload.ending_reason_version_id).to eq(original)
    expect(described_class.new(record).private_payload.dig('ending_reason_context', 'options')).to eq([entry.slice('code', 'name')])
    expect(described_class.new(record).private_payload.dig('ending_reason_context', 'required')).to be(true)
  end

  it 'rejects an unregistered legacy choice and retains the pending content for an explicit retry' do
    expect { manager.complete!(record, reason_code: 'resolved', outcome_code: 'completed') }
      .to raise_error(JrcContactCenter::OperationError, 'registered_ending_reason_required')
    expect(record.reload.completed_at).to be_nil
    expect(record.reason_code).to be_nil
    manager.complete!(record, reason_code: entry.fetch('code'), outcome_code: 'completed')
    expect(record.reload.reason_code).to eq(entry.fetch('code'))
    expect(record.completed_at).to be_present
  end

  it 'allows an empty pending draft but rejects an unregistered draft without silently losing the previous values' do
    revision = JrcContactCenter::QualificationDraftRevision.token(record)
    manager.save_draft!(record, { notes: 'SYNTHETIC pending' }, expected_revision: revision)
    expect(record.reload.notes).to eq('SYNTHETIC pending')
    revision = JrcContactCenter::QualificationDraftRevision.token(record)
    expect { manager.save_draft!(record, { reason_code: 'missing' }, expected_revision: revision) }
      .to raise_error(JrcContactCenter::OperationError, 'registered_ending_reason_required')
    expect(record.reload.notes).to eq('SYNTHETIC pending')
    expect(record.completed_at).to be_nil
  end

  it 'blocks direct SQL completion with an unregistered reason as well as the normal API path' do
    id = record.id
    expect do
      JrcContactCenter::Qualification.transaction(requires_new: true) do
        JrcContactCenter::Qualification.connection.execute("UPDATE jrc_contact_center_qualifications SET reason_code = 'missing', " \
                                                           "outcome_code = 'completed', completed_at = CURRENT_TIMESTAMP WHERE id = #{id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /Registered ending reason required/)
    expect(record.reload.completed_at).to be_nil
  end

  it 'blocks tampering with the original queue and requirement while preserving native closure of the ACW event' do
    origin = JrcContactCenter::AgentStateEvent.find_by!(account: account, external_event_id: "qualification:#{record.id}:pending")
    expect do
      origin.class.transaction(requires_new: true) do
        origin.class.connection.execute("UPDATE #{origin.class.table_name} SET metadata = metadata - 'ending_reason_snapshot_v1' " \
                                        "WHERE id = #{origin.id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /Ending reason original evidence is immutable/)
    manager.complete!(record, reason_code: entry.fetch('code'), outcome_code: 'completed')
    expect(origin.reload.ended_at).to be_present
    expect(origin.metadata.dig(described_class::KEY, 'required')).to be(true)
  end

  it 'does not let a supplied call version choose a catalogue or rewrite a previously unpinned call' do
    original = session.reload.ending_reason_version_id
    expect do
      session.class.transaction(requires_new: true) do
        session.class.connection.execute("UPDATE #{session.class.table_name} SET ending_reason_version_id = NULL WHERE id = #{session.id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /Call ending reason origin is immutable/)
    expect(session.reload.ending_reason_version_id).to eq(original)
  end

  it 'does not reopen a completed registered classification through direct SQL or rewrite its historical note' do
    manager.complete!(record, reason_code: entry.fetch('code'), outcome_code: 'completed', notes: 'SYNTHETIC final')
    original = record.reload.attributes
    expect do
      record.class.transaction(requires_new: true) do
        record.class.connection.execute("UPDATE #{record.class.table_name} SET completed_at = NULL, notes = 'changed' WHERE id = #{record.id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /Completed ending reason classification is immutable/)
    expect(record.reload.attributes).to eq(original)
  end

  it 'leaves another queue optional and accepts its explicitly started legacy reason without granting configuration access' do
    other = JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'SYNTHETIC-OTHER', name: 'SYNTHETIC other')
    call = JrcContactCenter::CallSession.create!(account: account, provider: 'synthetic', correlation_id: SecureRandom.uuid,
                                                 direction: 'inbound', status: 'ended', started_at: Time.current, ended_at: 1.minute.from_now,
                                                 current_unit: unit, current_queue: other)
    JrcContactCenter::CallLeg.create!(account: account, call_session: call, account_user: member, queue: other, direction: 'inbound',
                                      status: 'ended', started_at: call.started_at, answered_at: call.started_at, ended_at: call.ended_at)
    expect(JrcContactCenter::Qualification.where(call_session: call)).to be_empty
    pending = manager.start!(call_session: call)
    expect(described_class.new(pending).private_payload.dig('ending_reason_context', 'required')).to be(false)
    manager.complete!(pending, reason_code: 'resolved', outcome_code: 'completed')
    expect(pending.reload.completed_at).to be_present
  end

  it 'keeps the captured policy timestamp immutable independently of correctable operational timestamps' do
    call = session.reload
    captured = call.ending_reason_captured_started_at
    expect(captured).to eq(call.started_at)
    expect do
      call.class.transaction(requires_new: true) do
        call.class.connection.execute("UPDATE #{call.class.table_name} SET ending_reason_captured_started_at = started_at - INTERVAL '1 second' " \
                                      "WHERE id = #{call.id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /Call ending reason origin is immutable/)
    expect(call.reload.ending_reason_captured_started_at).to eq(captured)
  end

end

require 'rails_helper'

RSpec.describe JrcContactCenter::QualificationForms do
  include_context 'with an owned immutable operational ACW form'

  it 'captures one owned immutable response identity on the native qualification without another attendance or library' do
    state = service.state
    expect(state).to have_attributes(account_id: account.id, qualification_id: record.id, answers: {})
    expect(state.snapshot.fetch('origin')).to include('account_id' => account.id, 'account_user_id' => member.id, 'qualification_id' => record.id)
    JrcContactCenter::QualificationManager.ensure_voice!(record.call_session)
    expect(JrcContactCenter::QualificationForm.where(account: account).count).to eq(1)
    expect(JrcContactCenter::Qualification.where(account: account).count).to eq(1)
    expect(JrcContactCenter::AcwFormTemplate.where(account: account).count).to eq(1)
  end

  it 'exposes only the selected exact definition to the authorized caller and keeps private answers out of shared payloads' do
    expect(service.private_payload.dig('acw_form_context', 'selected')).to be_nil
    payload = service.private_payload(reason: 'order').fetch('acw_form_context')
    expect(payload.fetch('selected')).to include('form_id' => form.id.to_s, 'revision' => 1, 'rule_id' => rule[:id])
    expect(payload.fetch('selected').keys).not_to include('origin', 'actor_user_id', 'actor_account_user_id', 'request_id')
    expect(record.operational_payload).not_to have_key('acw_form_context')
    expect(JrcContactCenter::AgentStateSnapshot.new(account_user: member).call.to_json).not_to include(form.latest_version.name)
  end

  it 'saves incomplete typed responses with the native draft revision and retains false and zero without completing ACW' do
    previous = JrcContactCenter::QualificationDraftRevision.token(record)
    manager.save_draft!(record, { reason_code: 'order', acw_form_answers: { rule[:id] => { 'verified' => false, 'quantity' => 0 } } },
                        expected_revision: previous)
    expect(service.state.answers).to eq(rule[:id] => { 'verified' => false, 'quantity' => 0 })
    expect(record.reload.completed_at).to be_nil
    expect(JrcContactCenter::QualificationDraftRevision.token(record)).not_to eq(previous)
    expect(JrcContactCenter::AgentStateSnapshot.new(account_user: member).call[:state]).to eq('acw')
    expect(Audited.audit_class.where(auditable: record).pluck(:audited_changes).to_json).not_to include('verified', 'quantity')
  end

  it 'blocks native completion with a missing required form without partial manual fields or a state transition' do
    expect do
      manager.complete!(record, completion.except(:acw_form_answers))
    end.to raise_error(JrcContactCenter::AcwFormAnswers::Invalid)
    expect(record.reload.completed_at).to be_nil
    expect(record.reason_code).to be_nil
    expect(service.state.answers).to eq({})
    expect(JrcContactCenter::AgentStateEvent.where(account: account, state: 'available')).to be_empty
  end

  it 'cannot complete through a direct native model write while selected required answers are missing' do
    expect do
      record.update!(completed_at: Time.current, reason_code: 'order', outcome_code: 'completed')
    end.to raise_error(ActiveRecord::RecordInvalid, /invalid_acw_form_answers/)
    expect(record.reload.completed_at).to be_nil
    expect(service.state.answers).to eq({})
  end

  it 'completes only with the typed required fields and records the actual native available state' do
    manager.complete!(record, completion)
    expect(record.reload.completed_at).to be_present
    expect(service.state.answers).to eq(answers)
    expect(JrcContactCenter::AgentStateSnapshot.new(account_user: member).call[:state]).to eq('available')
    expect(service.private_payload(reason: 'order').dig('acw_form_context', 'answers')).to eq(answers)
    expect(record.operational_payload.to_json).not_to include('SYNTHETIC private response')
  end

  it 'retains responses for another reason across draft changes and reuses the exact original form on return' do
    manager.save_draft!(record, { reason_code: 'order', acw_form_answers: answers },
                        expected_revision: JrcContactCenter::QualificationDraftRevision.token(record))
    manager.save_draft!(record, { reason_code: 'resolved' }, expected_revision: JrcContactCenter::QualificationDraftRevision.token(record.reload))
    expect(service.state.answers).to eq(answers)
    expect(service.private_payload(reason: 'resolved').dig('acw_form_context', 'selected')).to be_nil
    expect(service.private_payload(reason: 'order').dig('acw_form_context', 'selected', 'revision')).to eq(1)
  end

  it 'does not reinterpret a captured attendance when the live policy removes its rule and binding' do
    previous = service.state.snapshot.deep_dup
    policy.update!({ voice: 240, whatsapp: 180 }, voice_rules: [], voice_form_bindings: [], expected_revision: policy.revision)
    manager.complete!(record, completion)
    expect(record.reload.acw_limit_seconds).to eq(120)
    expect(service.state.snapshot).to eq(previous)
    expect(service.state.answers).to eq(answers)
    expect(record.completed_at).to be_present
  end

  [nil, false, [], { 'unknown_rule' => {} }, { 'synthetic_form_rule' => false }].each do |invalid|
    it "rejects malformed or unknown form response keys #{invalid.inspect} atomically" do
      expect do
        manager.save_draft!(record, { reason_code: 'order', acw_form_answers: invalid },
                            expected_revision: JrcContactCenter::QualificationDraftRevision.token(record))
      end.to raise_error(JrcContactCenter::AcwFormAnswers::Invalid)
      expect(service.state.answers).to eq({})
      expect(record.reload.reason_code).to be_nil
    end
  end

  it 'does not bypass a required form with an arbitrary unknown classification in a new linked attendance' do
    expect do
      manager.complete!(record, completion.merge(reason_code: 'unregistered_synthetic_reason').except(:acw_form_answers))
    end.to raise_error(JrcContactCenter::OperationError, 'invalid_qualification_form_reason')
    expect(record.reload.completed_at).to be_nil
    expect(service.state.answers).to eq({})
  end

  it 'rejects a typed answer not present in the frozen schema while preserving all previous drafts' do
    manager.save_draft!(record, { reason_code: 'order', acw_form_answers: answers },
                        expected_revision: JrcContactCenter::QualificationDraftRevision.token(record))
    expect do
      manager.save_draft!(record, { acw_form_answers: { rule[:id] => { 'unknown' => 'SYNTHETIC' } } },
                          expected_revision: JrcContactCenter::QualificationDraftRevision.token(record.reload))
    end.to raise_error(JrcContactCenter::AcwFormAnswers::Invalid)
    expect(service.state.answers).to eq(answers)
  end
end

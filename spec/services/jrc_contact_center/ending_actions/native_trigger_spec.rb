require 'rails_helper'

RSpec.describe JrcContactCenter::EndingActions::NativeTrigger do
  subject(:readiness) { described_class.new(origin: origin) }

  include_context 'with native ending execution original evidence'

  let(:rule) do
    { 'timing' => 'acw_completed', 'reason_code' => 'SYNTHETIC_ORIGIN_REASON', 'conditions' => { 'outcome_codes' => [] } }
  end

  it 'does not treat a draft reason as explicit call-end confirmation or actual ACW completion' do
    original = origin
    JrcContactCenter::QualificationDraft.new(account: account, member: member).save!(
      qualification, { reason_code: 'SYNTHETIC_ORIGIN_REASON' },
      expected_revision: JrcContactCenter::QualificationDraftRevision.token(qualification)
    )
    expect(described_class.new(origin: original).call(rule.merge('timing' => 'call_end'))).to be_nil
    expect(readiness.call(rule)).to be_nil
    expect(qualification.reload.completed_at).to be_nil
  end

  it 'uses the immutable explicit classification timestamp and leaves ACW open' do
    original = origin
    JrcContactCenter::ConfirmEndingReason.new(account: account, member: member).call(
      qualification,
      attributes: { reason_code: 'SYNTHETIC_ORIGIN_REASON' },
      expected_revision: JrcContactCenter::QualificationDraftRevision.token(qualification), request_key: SecureRandom.uuid
    )
    confirmation = JrcContactCenter::EndingReasonConfirmation.find_by!(account: account, source_qualification_id: qualification.id)
    expected = { type: 'ending_reason_confirmation', id: confirmation.id, at: [original.created_at, confirmation.created_at].max,
                 reason_code: 'SYNTHETIC_ORIGIN_REASON', outcome_code: nil }
    expect(readiness.call(rule.merge('timing' => 'call_end'))).to eq(expected)
    expect(readiness.call(rule)).to be_nil
    expect(qualification.reload.completed_at).to be_nil
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'accepts a real native ACW completion without demanding an additional early confirmation' do
    original = origin
    complete_origin_qualification
    completion = JrcContactCenter::EndingActionCompletion.find_by!(account: account, origin: original)
    expected = { type: 'ending_action_completion', id: completion.id, at: completion.completed_at,
                 reason_code: completion.reason_code, outcome_code: completion.outcome_code }
    expect(readiness.call(rule)).to eq(expected)
    expect(readiness.call(rule.merge('timing' => 'call_end'))).to be_nil
    expect(JrcContactCenter::EndingReasonConfirmation.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'does not borrow a completion from another attendance of the same original actor' do
    other_call = new_origin_source_call
    JrcContactCenter::CallLeg.create!(account: account, call_session: other_call, account_user: member, queue: queue,
                                      direction: 'inbound', status: 'connected', started_at: other_call.started_at, answered_at: Time.current)
    other_call.update!(status: 'ended', ended_at: Time.current)
    other = JrcContactCenter::Qualification.find_by!(account: account, account_user: member, call_session: other_call)
    JrcContactCenter::QualificationManager.new(account: account, member: member).complete!(
      other, { reason_code: 'SYNTHETIC_ORIGIN_REASON', outcome_code: 'completed' }
    )
    first = origin
    expect(described_class.new(origin: first).call(rule)).to be_nil
    expect(qualification.reload.completed_at).to be_nil
  end

  it 'evaluates outcome conditions against the immutable actual completion rather than a draft result' do
    origin
    complete_origin_qualification
    expect(readiness.call(rule.merge('conditions' => { 'outcome_codes' => ['completed'] }))).to be_present
    expect(readiness.call(rule.merge('conditions' => { 'outcome_codes' => ['not_matching'] }))).to be_nil
  end

  it 'does not reinterpret a real completion as a different configured reason' do
    origin
    complete_origin_qualification
    expect(readiness.call(rule.merge('reason_code' => 'SYNTHETIC_DIFFERENT_REASON'))).to be_nil
  end

  it 'rejects an unknown trigger without converting it into an automatic call-end action' do
    expect { readiness.call(rule.merge('timing' => 'unknown')) }
      .to raise_error(JrcContactCenter::OperationError, 'ending_action_trigger_unavailable')
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end
end

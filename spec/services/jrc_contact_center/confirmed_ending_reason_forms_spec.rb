require 'rails_helper'

RSpec.describe 'Confirmed ending classification with incomplete native ACW forms' do
  include_context 'with a frozen ending reason catalogue'

  let(:rule_id) { 'synthetic_confirmation_form' }
  let(:service) { JrcContactCenter::QualificationForms.new(record) }

  before do
    form = JrcContactCenter::AcwFormTemplate.create!(account: account)
    JrcContactCenter::AcwFormVersion.create!(
      account: account, acw_form_template: form, revision: 1, name: 'SYNTHETIC ending confirmation form', description: '', status: 'active',
      definition: { 'fields' => [{ 'key' => 'verified', 'label' => 'SYNTHETIC verified', 'type' => 'boolean', 'required' => true },
                                { 'key' => 'quantity', 'label' => 'SYNTHETIC quantity', 'type' => 'integer', 'required' => true }] },
      actor_account_user_id: member.id, actor_user_id: actor.id, request_id: SecureRandom.uuid
    )
    rule = { id: rule_id, reason_code: entry.fetch('code'), scope: 'general', scope_id: nil, active: true, limit_seconds: 120 }
    binding = { rule_id: rule_id, form_id: form.id.to_s, revision: 1, required_fields: [] }
    policy.update!({ voice: 180, whatsapp: 180 }, voice_rules: [rule], voice_form_bindings: [binding], expected_revision: policy.revision)
  end

  it 'saves partial typed answers and confirms the reason while enforcing remaining required fields at actual ACW completion' do
    values = { reason_code: entry.fetch('code'), notes: 'SYNTHETIC draft', acw_form_answers: { rule_id => { 'verified' => false } } }
    JrcContactCenter::ConfirmEndingReason.new(account: account, member: member).call(
      record, attributes: values, expected_revision: JrcContactCenter::QualificationDraftRevision.token(record), request_key: SecureRandom.uuid
    )
    expect(service.state.answers).to eq(rule_id => { 'verified' => false })
    expect(record.reload.completed_at).to be_nil
    expect { manager.complete!(record, reason_code: entry.fetch('code'), outcome_code: 'completed') }
      .to raise_error(JrcContactCenter::AcwFormAnswers::Invalid)
    expect(record.reload.completed_at).to be_nil
    manager.complete!(record, reason_code: entry.fetch('code'), outcome_code: 'completed',
                              acw_form_answers: { rule_id => { 'verified' => false, 'quantity' => 0 } })
    expect(record.reload.completed_at).to be_present
    expect(service.state.answers).to eq(rule_id => { 'verified' => false, 'quantity' => 0 })
  end

  it 'does not partially save a reason or confirmation when submitted form answers are invalid' do
    values = { reason_code: entry.fetch('code'), acw_form_answers: { rule_id => { 'verified' => 'invented boolean' } } }
    expect do
      JrcContactCenter::ConfirmEndingReason.new(account: account, member: member).call(
        record, attributes: values, expected_revision: JrcContactCenter::QualificationDraftRevision.token(record), request_key: SecureRandom.uuid
      )
    end.to raise_error(JrcContactCenter::AcwFormAnswers::Invalid)
    expect(record.reload.reason_code).to be_nil
    expect(service.state.answers).to eq({})
    expect(JrcContactCenter::EndingReasonConfirmation.where(account: account)).to be_empty
  end
end

# Actual native callbacks and immutable form models; synthetic data only.
RSpec.shared_context 'with an owned immutable operational ACW form' do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:policy) { JrcContactCenter::AcwPolicy.new(account: account) }
  let(:manager) { JrcContactCenter::QualificationManager.new(account: account, member: member) }
  let(:definition) do
    { 'fields' => [
      { 'key' => 'feedback', 'label' => 'SYNTHETIC feedback', 'type' => 'text', 'required' => false },
      { 'key' => 'verified', 'label' => 'SYNTHETIC verified', 'type' => 'boolean', 'required' => true },
      { 'key' => 'quantity', 'label' => 'SYNTHETIC quantity', 'type' => 'integer', 'required' => true }
    ] }
  end
  let(:form) do
    JrcContactCenter::AcwFormTemplate.transaction do
      row = JrcContactCenter::AcwFormTemplate.create!(account: account)
      JrcContactCenter::AcwFormVersion.create!(
        account: account, acw_form_template: row, revision: 1, name: 'SYNTHETIC operational form', description: '', status: 'active',
        definition: definition, actor_account_user_id: member.id, actor_user_id: actor.id, request_id: SecureRandom.uuid
      )
      row
    end
  end
  let(:rule) { { id: 'synthetic_form_rule', reason_code: 'order', scope: 'general', scope_id: nil, active: true, limit_seconds: 120 } }
  let(:binding) { { rule_id: rule[:id], form_id: form.id.to_s, revision: 1, required_fields: ['feedback'] } }
  let(:record) { pending_pause_qualification }
  let(:service) { JrcContactCenter::QualificationForms.new(record) }
  let(:answers) { { rule[:id] => { 'feedback' => 'SYNTHETIC private response', 'verified' => false, 'quantity' => 0 } } }
  let(:completion) { { reason_code: 'order', outcome_code: 'completed', notes: 'SYNTHETIC native completion', acw_form_answers: answers } }

  before do
    account.enable_features!('jrc_contact_center')
    policy.update!({ voice: 180, whatsapp: 180 }, voice_rules: [rule], voice_form_bindings: [binding], expected_revision: policy.revision)
  end

  include_context 'with a native pending voice ACW for deferred pause'
end

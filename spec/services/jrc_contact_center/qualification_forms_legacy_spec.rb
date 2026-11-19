require 'rails_helper'

RSpec.describe JrcContactCenter::QualificationForms, 'native historical compatibility' do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:manager) { JrcContactCenter::QualificationManager.new(account: account, member: member) }

  before { account.enable_features!('jrc_contact_center') }

  include_context 'with a native pending voice ACW for deferred pause'

  it 'does not backfill a form or change a legacy manual token when policy bindings are introduced later' do
    record = pending_pause_qualification
    signature = JrcContactCenter::QualificationDraftRevision::FIELDS.map do |field|
      value = record.public_send(field)
      value.respond_to?(:iso8601) ? value.utc.iso8601(6) : value
    end
    original = Digest::SHA256.hexdigest(['qualification_manual_state_v1', signature].to_json)
    form = JrcContactCenter::AcwFormTemplate.create!(account: account)
    definition = { 'fields' => [{ 'key' => 'verified', 'label' => 'SYNTHETIC future required field', 'type' => 'boolean', 'required' => true }] }
    JrcContactCenter::AcwFormVersion.create!(
      account: account, acw_form_template: form, revision: 1, name: 'SYNTHETIC future form', description: '', status: 'active',
      definition: definition,
      actor_account_user_id: member.id, actor_user_id: actor.id, request_id: SecureRandom.uuid
    )
    policy = JrcContactCenter::AcwPolicy.new(account: account)
    rule = { id: 'synthetic', reason_code: 'order', scope: 'general', scope_id: nil, active: true, limit_seconds: 60 }
    binding = { rule_id: 'synthetic', form_id: form.id.to_s, revision: 1, required_fields: [] }
    policy.update!({ voice: 240, whatsapp: 180 }, voice_rules: [rule], voice_form_bindings: [binding], expected_revision: policy.revision)
    expect(JrcContactCenter::QualificationDraftRevision.token(record)).to eq(original)
    JrcContactCenter::QualificationManager.ensure_voice!(record.call_session)
    expect(JrcContactCenter::QualificationForm.where(qualification: record)).to be_empty
    manager.complete!(record, { reason_code: 'historical_external_reason', outcome_code: 'historical_result', notes: 'SYNTHETIC legacy' })
    expect(record.reload.completed_at).to be_present
    expect(record.acw_limit_seconds).to eq(180)
    expect(JrcContactCenter::QualificationForm.where(qualification: record)).to be_empty
  end
end

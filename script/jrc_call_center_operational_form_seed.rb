# Only used by the guarded exclusive Call Center synthetic runner, never by a product route.
class JrcContactCenter::SyntheticOperationalFormSeed
  def initialize(account:, admin:, queue:, reason_code: 'order', rule_id: 'synthetic-order')
    @account = account
    @admin = admin
    @queue = queue
    @reason_code = reason_code
    @rule_id = rule_id
  end

  def call
    context = { account: @account, account_user: @admin, user: @admin.user }
    writer = JrcContactCenter::AcwFormWrite.new(context: context)
    original = writer.call(input: input(1))
    form = original.fetch(:form)
    writer.call(input: input(2), id: form.id)
    policy = JrcContactCenter::AcwPolicy.new(account: @account)
    rule = { id: @rule_id, reason_code: @reason_code, scope: 'queue', scope_id: @queue.id, active: true, limit_seconds: 60 }
    binding = { rule_id: rule[:id], form_id: form.id.to_s, revision: 1, required_fields: ['feedback'] }
    policy.update!({ voice: 180, whatsapp: 180 }, voice_rules: [rule], voice_form_bindings: [binding], expected_revision: policy.revision)
    { form_id: form.id.to_s, original_form_revision: 1, latest_form_revision: 2, form_rule_id: rule[:id] }
  end

  private

  def input(revision)
    fields = [
      { 'key' => 'feedback', 'label' => 'SYNTHETIC feedback', 'type' => 'text', 'required' => false },
      { 'key' => 'verified', 'label' => 'SYNTHETIC verified', 'type' => 'boolean', 'required' => true },
      { 'key' => 'quantity', 'label' => 'SYNTHETIC quantity', 'type' => 'integer', 'required' => true }
    ]
    fields << { 'key' => 'new_note', 'label' => 'SYNTHETIC future field', 'type' => 'text', 'required' => false } if revision == 2
    JrcContactCenter::AcwFormInput.new(name: "SYNTHETIC operational version #{revision}", description: 'SYNTHETIC native fixture',
                                       status: 'active', definition: { 'fields' => fields }, request_id: SecureRandom.uuid,
                                       expected_revision: revision - 1)
  end
end

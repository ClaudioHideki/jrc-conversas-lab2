# frozen_string_literal: true

# Optional references inside the existing ACW policy, not a second form registry.
class JrcContactCenter::AcwFormBindingPolicy
  KEY = 'voice_form_bindings'
  SIGNATURE_VERSION = 'voice_form_bindings_v1'

  def initialize(account:)
    @account = account
  end

  def call
    stored = @account.settings.fetch(JrcContactCenter::AcwPolicy::KEY, {}).fetch(KEY, [])
    rules = JrcContactCenter::AcwScopedRules.new(account: @account).call
    JrcContactCenter::AcwFormBindings.new(account: @account).references!(stored, rules: rules)
  end

  def signature(legacy)
    rows = call
    return legacy if rows.empty?

    values = rows.map { |row| JrcContactCenter::AcwFormBindings::PIN_FIELDS.map { |field| row.fetch(field) } }
    legacy + [[SIGNATURE_VERSION, values]]
  end

  # Builds proposed settings only; the existing policy transaction owns persistence,
  # authority, revision validation and audit. Preserved pins come from this Account.
  def propose(settings:, bindings:, rules:)
    validator = JrcContactCenter::AcwFormBindings.new(account: @account)
    previous = call
    rows = if bindings == :unchanged
             validator.references!(previous, rules: rules)
           else
             validator.validate!(bindings, rules: rules, preserved: previous)
           end
    rows.empty? ? settings.except(KEY) : settings.merge(KEY => rows)
  end
end

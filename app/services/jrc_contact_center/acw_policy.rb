# frozen_string_literal: true

class JrcContactCenter::AcwPolicy
  # Preserve required tabulation for existing Accounts. A manually started
  # qualification still requires its reason/result even when voice is optional.
  DEFAULTS = { 'voice' => 180, 'whatsapp' => 180 }.freeze
  KEY = 'jrc_contact_center_acw'

  def initialize(account:)
    @account = account
  end

  def call
    { enabled: @account.feature_enabled?('jrc_contact_center'), voice_required: voice_required?, require_reason: true, require_result: true,
      limits: DEFAULTS.merge(@account.settings.fetch(KEY, {}).slice(*DEFAULTS.keys)) }
  end

  # Only effective ACW state and Account identity; unrelated settings are excluded.
  def revision
    policy = call
    values = DEFAULTS.keys.map { |key| policy.fetch(:limits).fetch(key) }
    signature = [KEY, @account.id, policy.fetch(:voice_required), values]
    scoped = JrcContactCenter::AcwScopedRules.new(account: @account).call
    signature << scoped.map { |row| JrcContactCenter::AcwRulePrecedence::FIELDS.map { |field| row.fetch(field) } } if scoped.any?
    signature = JrcContactCenter::AcwEndingReasons.new(account: @account).signature(signature)
    signature = JrcContactCenter::EndingActions::Catalogue.new(account: @account).signature(signature)
    Digest::SHA256.hexdigest(JrcContactCenter::AcwFormBindingPolicy.new(account: @account).signature(signature).to_json)
  end

  def voice_required?
    @account.settings.fetch(KEY, {}).fetch('voice_required', true) != false
  end

  def update!(attributes = nil, voice_required: :unchanged, expected_revision: :legacy, voice_rules: :unchanged, **legacy_limits)
    extended = legacy_limits.extract!(:voice_form_bindings, :voice_reason_catalog, :voice_reason_required_queue_ids, :voice_reason_confirmation)
    values = validated_limits(attributes || legacy_limits)
    raise JrcContactCenter::OperationError, 'invalid_acw_policy' unless [true, false, :unchanged].include?(voice_required)

    @account.with_lock do
      JrcContactCenter::ConfigurationRevision.check_token!(revision, expected_revision) unless expected_revision == :legacy
      before = JrcContactCenter::AcwPolicyAudit.capture(@account)
      current = updated_settings(values, voice_required, voice_rules, expected_revision)
      current = extended_settings(current, extended, expected_revision)
      @account.update!(settings: @account.settings.merge(KEY => current))
      JrcContactCenter::AcwPolicyAudit.write!(account: @account, before: before, after: JrcContactCenter::AcwPolicyAudit.capture(@account))
    end
    call
  end

  private

  def extended_settings(settings, options, expected_revision)
    current = form_settings(settings, options.fetch(:voice_form_bindings, :unchanged), expected_revision)
    reason_settings(current, options, expected_revision)
  end

  def reason_settings(settings, options, expected_revision)
    entries = options.fetch(:voice_reason_catalog, :unchanged)
    queues = options.fetch(:voice_reason_required_queue_ids, :unchanged)
    JrcContactCenter::ConfigurationRevision.check_token!(revision, expected_revision) unless entries == :unchanged && queues == :unchanged
    JrcContactCenter::AcwEndingReasons.new(account: @account).propose(
      settings: settings, entries: entries, required_queue_ids: queues, activation_confirmed: options.fetch(:voice_reason_confirmation, false)
    )
  end

  def form_settings(settings, bindings, expected_revision)
    JrcContactCenter::ConfigurationRevision.check_token!(revision, expected_revision) unless bindings == :unchanged
    rules = settings.fetch(JrcContactCenter::AcwScopedRules::KEY, [])
    JrcContactCenter::AcwFormBindingPolicy.new(account: @account).propose(settings: settings, bindings: bindings, rules: rules)
  end

  def updated_settings(values, voice_required, voice_rules, expected_revision)
    current = @account.settings.fetch(KEY, {}).merge(values)
    current['voice_required'] = voice_required unless voice_required == :unchanged
    return current if voice_rules == :unchanged

    JrcContactCenter::ConfigurationRevision.check_token!(revision, expected_revision)
    current[JrcContactCenter::AcwScopedRules::KEY] = JrcContactCenter::AcwScopedRules.new(account: @account).validate!(voice_rules)
    current
  end

  def validated_limits(attributes)
    values = attributes.to_h.transform_keys(&:to_s).slice(*DEFAULTS.keys)
    unless values.size == DEFAULTS.size && values.values.all? { |value| value.is_a?(Integer) && value.between?(1, 3600) }
      raise JrcContactCenter::OperationError, 'invalid_acw_policy'
    end

    values
  end
end

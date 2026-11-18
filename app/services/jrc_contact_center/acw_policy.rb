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
    signature << scoped if scoped.any?
    Digest::SHA256.hexdigest(signature.to_json)
  end

  def voice_required?
    @account.settings.fetch(KEY, {}).fetch('voice_required', true) != false
  end

  def update!(attributes = nil, voice_required: :unchanged, expected_revision: :legacy, voice_rules: :unchanged, **legacy_limits)
    values = validated_limits(attributes || legacy_limits)
    raise JrcContactCenter::OperationError, 'invalid_acw_policy' unless [true, false, :unchanged].include?(voice_required)

    @account.with_lock do
      JrcContactCenter::ConfigurationRevision.check_token!(revision, expected_revision) unless expected_revision == :legacy
      before = JrcContactCenter::AcwPolicyAudit.capture(@account)
      current = updated_settings(values, voice_required, voice_rules, expected_revision)
      @account.update!(settings: @account.settings.merge(KEY => current))
      JrcContactCenter::AcwPolicyAudit.write!(account: @account, before: before, after: JrcContactCenter::AcwPolicyAudit.capture(@account))
    end
    call
  end

  private

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

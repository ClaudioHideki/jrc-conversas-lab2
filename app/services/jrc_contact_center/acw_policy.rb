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

  def voice_required?
    @account.settings.fetch(KEY, {}).fetch('voice_required', true) != false
  end

  def update!(attributes = nil, voice_required: :unchanged, **legacy_limits)
    values = (attributes || legacy_limits).to_h.transform_keys(&:to_s).slice(*DEFAULTS.keys)
    unless values.size == DEFAULTS.size && values.values.all? { |value| value.is_a?(Integer) && value.between?(1, 3600) }
      raise JrcContactCenter::OperationError, 'invalid_acw_policy'
    end
    raise JrcContactCenter::OperationError, 'invalid_acw_policy' unless [true, false, :unchanged].include?(voice_required)

    @account.with_lock do
      current = @account.settings.fetch(KEY, {}).merge(values)
      current['voice_required'] = voice_required unless voice_required == :unchanged
      @account.update!(settings: @account.settings.merge(KEY => current))
    end
    call
  end
end

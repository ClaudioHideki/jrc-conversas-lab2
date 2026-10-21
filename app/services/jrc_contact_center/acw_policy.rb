# frozen_string_literal: true

class JrcContactCenter::AcwPolicy
  # Backend defaults, per Account. Both fields always required in this release.
  DEFAULTS = { 'voice' => 180, 'whatsapp' => 180 }.freeze
  KEY = 'jrc_contact_center_acw'

  def initialize(account:)
    @account = account
  end

  def call
    { enabled: @account.feature_enabled?('jrc_contact_center'), require_reason: true, require_result: true,
      limits: DEFAULTS.merge(@account.settings.fetch(KEY, {}).slice(*DEFAULTS.keys)) }
  end

  def update!(attributes)
    values = attributes.to_h.stringify_keys.slice(*DEFAULTS.keys)
    unless values.size == DEFAULTS.size && values.values.all? { |value| value.is_a?(Integer) && value.between?(1, 3600) }
      raise JrcContactCenter::OperationError, 'invalid_acw_policy'
    end

    @account.with_lock { @account.update!(settings: @account.settings.merge(KEY => values)) }
    call
  end
end

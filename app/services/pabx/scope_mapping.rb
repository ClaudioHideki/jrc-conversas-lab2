# A mapping is an Account-local, server-authorized contract, never a value
# inferred from a dashboard response. Existing identity mappings remain strict.
class Pabx::ScopeMapping
  KEY = 'scope_mapping'.freeze
  FIELDS = %w[account_id tenant accountcode cdr_identity authorized_by_id authorized_at].freeze
  IDENTIFIER = /\A[0-9A-Za-z_-]{1,64}\z/

  def self.authorize(integration:, actor:, accountcode:, cdr_identity:)
    raise Pundit::NotAuthorizedError unless actor.is_a?(SuperAdmin)

    { 'account_id' => integration.account_id, 'tenant' => integration.pabx_settings.fetch('expected_tenant').to_s,
      'accountcode' => accountcode.to_s, 'cdr_identity' => cdr_identity.to_s,
      'authorized_by_id' => actor.id, 'authorized_at' => Time.current.iso8601 }
  end

  def initialize(integration)
    @integration = integration
    @settings = integration.pabx_settings
  end

  def validate!
    return unless @settings.key?(KEY)

    row = @settings[KEY]
    valid = row.is_a?(Hash) && row.keys.sort == FIELDS.sort && row['account_id'] == @integration.account_id &&
            row['tenant'] == @settings['expected_tenant'].to_s && IDENTIFIER.match?(row['tenant'].to_s) &&
            IDENTIFIER.match?(row['accountcode'].to_s) && %w[tenant accountcode].include?(row['cdr_identity']) &&
            row['authorized_by_id'].is_a?(Integer) && SuperAdmin.exists?(id: row['authorized_by_id']) &&
            row['authorized_at'].is_a?(String)
    raise Pabx::Error, 'INVALID_SCOPE_MAPPING' unless valid

    Time.iso8601(row.fetch('authorized_at'))
  rescue ArgumentError
    raise Pabx::Error, 'INVALID_SCOPE_MAPPING'
  end

  def accountcode
    validate!
    @settings.key?(KEY) ? @settings.fetch(KEY).fetch('accountcode') : @settings.fetch('expected_tenant').to_s
  end

  def matches?(returned)
    returned.to_s == accountcode
  end

  def cdr_matches?(returned)
    validate!
    row = @settings[KEY]
    expected = row && row['cdr_identity'] == 'accountcode' ? accountcode : @settings.fetch('expected_tenant').to_s
    returned.to_s == expected
  end
end

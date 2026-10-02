class JrcCustomers::TaxLookup
  class Unconfigured < StandardError; end
  FIELDS = %w[name trade_name tax_id state_registration municipal_registration segment website email phone_number].freeze

  def self.configured?
    Rails.application.config.x.jrc_customer_master.tax_lookup_provider.respond_to?(:call)
  end

  def self.call(account:, tax_id:)
    provider = Rails.application.config.x.jrc_customer_master.tax_lookup_provider
    raise Unconfigured, 'No optional CNPJ provider configured' unless configured?
    normalized = JrcCustomers::TaxIdentifier.normalize(tax_id)
    raise ArgumentError, 'Invalid CNPJ' unless normalized && JrcCustomers::TaxIdentifier.cnpj_valid?(normalized)

    result = provider.call(account: account, tax_id: normalized)
    raise ArgumentError, 'Provider must return an object' unless result.is_a?(Hash)
    # A provider returns suggestions; it cannot persist or decide company identity through this adapter.
    result.stringify_keys.slice(*FIELDS).transform_values { |value| value.to_s.first(1000) }
  end
end

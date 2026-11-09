# frozen_string_literal: true

class JrcCustomers::EstablishmentMetadata
  KEY = 'jrc_establishment'
  FIELDS = %w[store_code cluster phones].freeze

  def self.read(company)
    company.additional_attributes.fetch(KEY, {}).slice(*FIELDS)
  end

  def self.attributes(company, input)
    attrs = input.to_h.stringify_keys
    return attrs unless attrs.key?('establishment')

    values = attrs.delete('establishment')
    raise ArgumentError, 'Invalid establishment fields' unless values.is_a?(Hash)

    values = values.stringify_keys
    raise ArgumentError, 'Invalid establishment fields' unless (values.keys - FIELDS).empty?

    code = values.fetch('store_code')
    cluster = values.fetch('cluster')
    phones = values.fetch('phones', [])
    valid = code.is_a?(String) && code.strip.length.between?(1, 80) && cluster.is_a?(String) && cluster.strip.length.between?(1, 255)
    valid &&= phones.is_a?(Array) && phones.size <= 20 && phones.all? { |phone| phone.is_a?(String) && JrcCustomers::Identity.phone(phone, country: 'BR') }
    raise ArgumentError, 'Invalid establishment code, cluster or phones' unless valid

    data = { 'store_code' => code.strip, 'cluster' => cluster.strip,
             'phones' => phones.map { |phone| JrcCustomers::Identity.phone(phone, country: 'BR') }.uniq }
    attrs.merge('additional_attributes' => company.additional_attributes.merge(KEY => data))
  end

  def self.scope(account)
    JrcCustomers::Company.where(account_id: account.id, active: true)
      .where("COALESCE(additional_attributes -> 'jrc_establishment' ->> 'store_code', '') <> ''")
  end

  def self.snapshot(company)
    read(company).merge('id' => company.id.to_s, 'name' => company.trade_name.presence || company.name,
                       'legal_name' => company.name, 'cnpj' => company.tax_id)
  end
end

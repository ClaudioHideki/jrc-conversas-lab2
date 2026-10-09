class JrcRelationship::CommercialEligibility
  def self.reason(contracts, account:, product_id: nil)
    active = contracts.where(status: %w[active expiring], signature_status: 'signed')
    return 'active_contract_missing' unless active.exists?

    products = account.jrc_crm_products.active
    products = products.where(id: product_id) if product_id.present?
    items = JrcCrm::ContractItem.where(contract_id: active.select(:id), product_id: products.select(:id), status: 'active')
    items.exists? ? nil : 'active_product_missing'
  end

  def self.exception?(value, account:)
    value.is_a?(Hash) && value['reason'].is_a?(String) && value['reason'].strip.length.between?(1, 2000) &&
      value['approved_at'].present? && account.users.exists?(id: value['approved_by_id'])
  end
end

module JrcCrm::CorporateUnitBinding
  extend ActiveSupport::Concern

  included do
    validate :validate_corporate_unit_binding
  end

  private

  def validate_corporate_unit_binding
    units = JrcCrm::BusinessUnit.where(account_id: account_id)
    validate_unit_account(units)
    preserve_issuer_unit(units)
    validate_deal_unit_metadata(units) if is_a?(JrcCrm::Deal)
  end

  def validate_unit_account(units)
    errors.add(:business_unit_id, 'must belong to this account') if business_unit_id.present? && !units.exists?(id: business_unit_id)
  end

  def preserve_issuer_unit(units)
    previous = business_unit_id_in_database
    return unless persisted? && business_unit_id.blank? && previous && units.where.not(company_id: nil).exists?(id: previous)

    errors.add(:business_unit_id, 'cannot remove an established issuer')
  end

  def validate_deal_unit_metadata(units)
    return if metadata['business_unit_id'].blank?

    reference = metadata['business_unit_id'].to_s
    valid = reference.match?(/\A[1-9]\d*\z/) && units.exists?(id: reference)
    valid &&= reference == business_unit_id.to_s if business_unit_id
    errors.add(:metadata, 'must use the same native business unit') unless valid
  end
end

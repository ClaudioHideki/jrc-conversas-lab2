module JrcCrm::CommercialGratuityIntent
  extend ActiveSupport::Concern
  TYPES = %w[installation monthly_fee product service benefit promotion bonus].freeze

  def self.valid_payload?(data)
    data == {} || (data.is_a?(Hash) && data.keys.sort == %w[reason type] && TYPES.include?(data['type']) && valid_reason?(data['reason']))
  end

  def self.valid_reason?(reason)
    reason.is_a?(String) && reason.strip.length.between?(3, 500)
  end

  included do
    validate :commercial_gratuity_is_typed
  end

  private

  # A persisted draft is not approval. CommercialGate blocks effects until both votes.
  def declared_free_draft?
    data = commercial_gratuity
    resource = respond_to?(:proposal) ? proposal : deal
    unit = JrcApprovals::CommercialCatalog.business_unit(resource)
    unit&.company_id && unit_price_cents.to_i.zero? && JrcCrm::CommercialGratuityIntent.valid_payload?(data) &&
      (TYPES - ['installation']).include?(data['type'])
  end

  def commercial_gratuity_is_typed
    data = commercial_gratuity
    valid = JrcCrm::CommercialGratuityIntent.valid_payload?(data)
    errors.add(:commercial_gratuity, 'requires a commercial type and explicit reason') unless valid
  end
end

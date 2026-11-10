# Only installed native mutations may be reached through an approval. Never
# constantize a resource_type supplied by a caller or infer editable fields.
class JrcApprovals::AdjustmentSources
  SOURCES = {
    'crm.proposal_send' => 'JrcCrm::Proposal',
    'crm.proposal_convert' => 'JrcCrm::Proposal',
    'crm.order_price' => 'JrcCrm::SalesOrder',
    'crm.proposal_terms' => 'JrcCrm::Proposal', 'crm.order_terms' => 'JrcCrm::SalesOrder'
  }.freeze
  FIELDS = %w[discount_cents].freeze

  def self.type!(key:, resource_type:)
    expected = SOURCES[key]
    raise JrcApprovals::Error, 'ADJUSTMENT_NOT_SUPPORTED' unless expected && expected == resource_type

    expected
  end

  def self.order_mutable?(status:, terms_locked:, invoiced:)
    %w[draft pending].include?(status) && terms_locked == false && invoiced == false
  end

  def self.discount!(changes)
    value = changes.is_a?(Hash) && changes['discount_cents']
    unless changes.is_a?(Hash) && changes.keys == FIELDS && value.is_a?(Integer) &&
           value.between?(0, JrcApprovals::TierRanges::MAX_EXACT_BOUND)
      raise JrcApprovals::Error, 'INVALID_ADJUSTMENT_FIELDS'
    end
    value
  end
end

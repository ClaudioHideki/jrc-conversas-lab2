# Existing legacy requirements shared by controller and effect service.
# This is not a new configurable commercial policy.
class JrcCrm::ProposalApprovalRequirements
  def initialize(proposal)
    @proposal = proposal
  end

  def commercial?
    general = @proposal.subtotal_cents.to_i.zero? ? 0.0 : (@proposal.discount_cents.to_f / @proposal.subtotal_cents.to_i) * 100
    general > 10 || @proposal.proposal_items.any? do |item|
      threshold = item.product&.discount_approval_percent.to_f
      percent = item.gross_line_total_cents.zero? ? 0.0 : (item.applied_discount_cents.to_f / item.gross_line_total_cents) * 100
      threshold.positive? && percent > threshold
    end
  end

  def financial?
    return false if @proposal.subtotal_cents.to_i.zero?

    (@proposal.total_discount_cents.to_f / @proposal.subtotal_cents.to_i) * 100 > 10
  end

  def technical?
    @proposal.proposal_items.any? { |item| item.product&.requires_contract? || item.product&.technical_requirements.present? }
  end

  def required?
    commercial? || financial? || technical?
  end
end

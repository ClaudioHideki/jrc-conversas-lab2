# Native applied receipts are DB-protected. Verify their exact revision chain;
# they permit continuity only for this review's own membership changes.
class JrcRelationship::PortfolioMembershipProgress
  def self.call(review)
    pin = review.snapshot.fetch('group_membership')
    revision = pin.fetch('initial_revision')
    links = pin.fetch('links').deep_dup
    review.items.where(state: 'applied').order(:ordinal).each do |item|
      expected = expected_receipt(review, item, revision, links)
      unless item.receipt.is_a?(Hash) && item.receipt.slice(*expected.keys) == expected
        raise JrcRelationship::BatchReviewError.new('BATCH_RECEIPT_INVALID', 'Reviewed portfolio receipt changed')
      end

      revision = expected.fetch('group_version')
      links[item.assignment_id.to_s] = review.inputs.fetch('active')
    end
    { revision: revision, links: links }
  end

  def self.expected_receipt(review, item, revision, links)
    active = review.inputs.fetch('active')
    changed = links.fetch(item.assignment_id.to_s) != active
    state = if active
              changed ? 'linked' : 'already_linked'
            else
              changed ? 'unlinked' : 'already_unlinked'
            end
    { 'operation' => 'portfolio_membership', 'assignment_id' => item.assignment_id,
      'portfolio_group_id' => review.snapshot.fetch('group_membership').fetch('portfolio_group_id'),
      'group_revision_before' => revision, 'group_version' => revision + (changed ? 1 : 0), 'membership_state' => state }
  end
  private_class_method :expected_receipt
end

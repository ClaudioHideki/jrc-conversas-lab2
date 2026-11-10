# Only this review's immutable receipts can account for its own revision and
# newly created allocation IDs. No receipt grants source visibility.
class JrcRelationship::MasterAllocationProgress
  def self.call(review)
    pin = review.snapshot.fetch('master_group')
    revision = pin.fetch('initial_revision')
    applied = {}
    review.items.where(state: 'applied').order(:ordinal).each do |item|
      row = review.snapshot.fetch('rows').fetch(item.ordinal)
      expected = expected_receipt(item, row, pin, revision)
      validate_receipt!(item, row, expected)

      revision = expected.fetch('group_version')
      applied[item.company_id] = item.receipt
    end
    { revision: revision, applied: applied }
  end

  def self.expected_receipt(item, row, pin, revision)
    changed = !row.fetch('linked')
    { 'operation' => 'master_allocation', 'company_id' => item.company_id, 'assignment_id' => item.assignment_id,
      'portfolio_group_id' => pin.fetch('portfolio_group_id'), 'group_revision_before' => revision,
      'group_version' => revision + (changed ? 1 : 0), 'membership_state' => changed ? 'linked' : 'already_linked',
      'allocation_state' => row.fetch('mode') == 'create' ? 'created' : 'reused' }
  end

  def self.validate_receipt!(item, row, expected)
    valid = valid_identity?(item, row, expected)
    if row.fetch('mode') == 'reuse'
      valid &&= item.assignment_id == row.fetch('assignment_id') && item.receipt['assignment_digest'] == row.fetch('digest')
    end
    raise JrcRelationship::BatchReviewError.new('BATCH_RECEIPT_INVALID', 'Reviewed master receipt changed') unless valid
  end

  def self.valid_identity?(item, row, expected)
    item.receipt.is_a?(Hash) && item.receipt.slice(*expected.keys) == expected && item.company_id == row.fetch('company_id') &&
      item.assignment_id && /\A[a-f0-9]{64}\z/.match?(item.receipt['assignment_digest'].to_s)
  end
  private_class_method :expected_receipt, :validate_receipt!, :valid_identity?
end

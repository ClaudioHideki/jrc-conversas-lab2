require 'rails_helper'

RSpec.describe JrcRelationship::BatchReviewError do
  it 'projects only allowlisted diagnostics instead of arbitrary exception messages or codes' do
    secret = 'Synthetic private validation content; never publish this value'
    expect(described_class.item_code(ArgumentError.new(secret))).to eq('BATCH_NATIVE_OPERATION_FAILED')
    expect(described_class.item_code(described_class.new(secret, secret))).to eq('BATCH_NATIVE_OPERATION_FAILED')
    expect(described_class.item_code(described_class.new('BATCH_RECEIPT_INVALID', secret))).to eq('BATCH_RECEIPT_INVALID')
    expect(described_class.new('BATCH_REVIEW_STALE', secret)).to be_a(ArgumentError)
  end

  it 'uses typed native validation details and never matches a translated or private message' do
    record = JrcRelationship::Assignment.new
    record.errors.add(:owner, :portfolio_capacity_unconfigured, message: 'Synthetic private owner name')
    expect(described_class.item_code(ActiveRecord::RecordInvalid.new(record))).to eq('BATCH_CAPACITY_UNCONFIGURED')
    record.errors.clear
    record.errors.add(:owner, 'portfolio_capacity_exceeded Synthetic private string')
    expect(described_class.item_code(ActiveRecord::RecordInvalid.new(record))).to eq('BATCH_NATIVE_VALIDATION_FAILED')
    record.errors.clear
    record.errors.add(:owner, :portfolio_capacity_unavailable)
    expect(described_class.item_code(ActiveRecord::RecordInvalid.new(record))).to eq('BATCH_CAPACITY_UNAVAILABLE')
  end
end

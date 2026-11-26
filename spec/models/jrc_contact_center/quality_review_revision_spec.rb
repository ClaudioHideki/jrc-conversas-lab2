# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcContactCenter::QualityReviewRevision, :pabx do
  include_context 'with native authorized quality review source'

  let(:snapshot) { JrcContactCenter::QualityAnalysisSnapshot.new(analysis: analysis, authorized_call_id: record.external_unique_id) }
  let(:values) do
    { 'classification' => 'negative', 'adjusted_summary' => 'SYNTHETIC correction', 'adjusted_themes' => [], 'recommendation_ids' => [],
      'justification' => 'SYNTHETIC justification', 'expected_revision' => 0, 'expected_source_sha256' => snapshot.sha256,
      'request_id' => SecureRandom.uuid }
  end
  let(:revision) { JrcContactCenter::QualityReviewWrite.new(account: account, member: member).call(record.id, values) }

  # Explicit SQL is essential here: prove that PostgreSQL protects history even without model callbacks.
  def insert_native_revision(attributes)
    connection = ApplicationRecord.connection
    columns = attributes.keys.map { |key| connection.quote_column_name(key) }.join(', ')
    json_fields = %w[original_analysis reviewed_values scope_snapshot]
    values = attributes.map { |key, value| connection.quote(json_fields.include?(key) ? JSON.generate(value) : value) }.join(', ')
    connection.execute("INSERT INTO #{connection.quote_table_name(described_class.table_name)} (#{columns}) VALUES (#{values})")
  end

  it 'rejects SQL updates and individual deletion while preserving the exact original history' do
    original = revision.attributes
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute("UPDATE #{described_class.table_name} SET revision = 8 WHERE id = #{Integer(revision.id)}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /history is immutable/)
    expect do
      ApplicationRecord.transaction(requires_new: true) { described_class.where(id: revision.id).delete_all }
    end.to raise_error(ActiveRecord::StatementInvalid, /history is immutable/)
    expect(revision.reload.attributes).to eq(original)
  end

  it 'refuses an inserted duplicate counter or skipped history revision through direct SQL' do
    attributes = revision.attributes.except('id').merge('request_key' => SecureRandom.uuid)
    [1, 9].each do |number|
      expect do
        ApplicationRecord.transaction(requires_new: true) { insert_native_revision(attributes.merge('revision' => number)) }
      end.to raise_error(ActiveRecord::StatementInvalid, /revision conflict/)
    end
    expect(described_class.where(account: account).pluck(:revision)).to eq([1])
  end

  it 'refuses a foreign account or actor rather than accepting positive identifiers' do
    attributes = revision.attributes.except('id').merge('revision' => 2, 'request_key' => SecureRandom.uuid)
    foreign = create(:account)
    [attributes.merge('account_id' => foreign.id), attributes.merge('actor_user_id' => create(:user).id)].each do |input|
      expect do
        ApplicationRecord.transaction(requires_new: true) { insert_native_revision(input) }
      end.to raise_error(ActiveRecord::StatementInvalid, /Quality review/)
    end
    expect(described_class.where(account: account).count).to eq(1)
    expect(described_class.where(account: foreign)).to be_empty
  end

  it 'rejects missing required JSON fields rather than allowing SQL NULL to satisfy a CHECK' do
    attributes = revision.attributes.except('id').merge('revision' => 2, 'request_key' => SecureRandom.uuid, 'reviewed_values' => {})
    expect do
      ApplicationRecord.transaction(requires_new: true) { insert_native_revision(attributes) }
    end.to raise_error(ActiveRecord::StatementInvalid, /cc_quality_review_/)
    expect(described_class.where(account: account).count).to eq(1)
  end

  it 'does not add user, membership or recording foreign keys that can cascade away immutable human history' do
    revision
    keys = ApplicationRecord.connection.foreign_keys(described_class.table_name)
    expect(keys.map(&:to_table)).to eq(['accounts'])
    expect(keys.sole.on_delete).to eq(:cascade)
  end
end

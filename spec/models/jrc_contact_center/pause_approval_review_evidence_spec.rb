require 'rails_helper'

RSpec.describe JrcContactCenter::PauseApprovalReview, :approval_core do
  include_context 'with all-scope native pause approval'

  let(:review) do
    publish_all_pause_policies
    row = create_reviewed_pause
    described_class.find_by!(account: account, deferred_pause_request_id: row.id)
  end

  def connection
    described_class.connection
  end

  def guarded_sql(statement)
    described_class.transaction(requires_new: true) { connection.execute(statement) }
  end

  it 'retains the complete native payload and scope set unchanged in PostgreSQL' do
    original = review.payload.deep_dup
    expected = review.context_digest
    connection.execute('SET CONSTRAINTS cc_pause_approval_review_complete, cc_pause_approval_scope_complete IMMEDIATE')
    expect(review.reload.payload).to eq(original)
    expect(JrcApprovals::Ledger.digest(review.payload)).to eq(expected)
    expect(review.scopes.count).to eq(2)
    expect(review.scopes.order(:id).flat_map(&:unit_ids)).to eq(units.map { |unit| unit.id.to_s })
  end

  it 'rejects bulk edits to the immutable complete context without silently rewriting a historical approval' do
    review
    expect do
      guarded_sql("UPDATE jrc_contact_center_pause_approval_reviews SET context_digest='#{'f' * 64}' " \
                  "WHERE account_id=#{account.id} AND id=#{review.id}")
    end.to raise_error(ActiveRecord::StatementInvalid, /Pause approval evidence is immutable/)
    expect(review.reload.context_digest).not_to eq('f' * 64)
  end

  it 'rejects scope movement between accounts using actual SQL rather than an ActiveRecord-only validation' do
    scope = review.scopes.first!
    other = create(:account)
    expect do
      guarded_sql("UPDATE jrc_contact_center_pause_approval_scopes SET account_id=#{other.id} " \
                  "WHERE account_id=#{account.id} AND id=#{scope.id}")
    end.to raise_error(ActiveRecord::StatementInvalid, /Pause approval evidence is immutable/)
    expect(scope.reload.account_id).to eq(account.id)
  end

  it 'does not allow deleting one scope from an existing live-account approval history' do
    scope = review.scopes.first!
    expect do
      guarded_sql("DELETE FROM jrc_contact_center_pause_approval_scopes WHERE account_id=#{account.id} AND id=#{scope.id}")
    end.to raise_error(ActiveRecord::StatementInvalid, /Pause approval evidence is immutable/)
    expect(review.scopes.count).to eq(2)
  end

  it 'rejects deleting the immutable source review while its native account remains present' do
    review
    expect do
      guarded_sql("DELETE FROM jrc_contact_center_pause_approval_reviews WHERE account_id=#{account.id} AND id=#{review.id}")
    end.to raise_error(ActiveRecord::StatementInvalid, /Pause approval evidence is immutable/)
    expect(described_class.exists?(review.id)).to be(true)
  end

  it 'keeps the exact additive migration receipt valid on reexecution without changing history or any original table' do
    require Rails.root.join('db/migrate/20261122120000_create_contact_center_pause_approval_evidence')
    original = review.attributes.deep_dup
    scopes = review.scopes.order(:id).map(&:attributes)
    expect { CreateContactCenterPauseApprovalEvidence.new.up }.not_to(change(described_class, :count))
    expect(review.reload.attributes).to eq(original)
    expect(review.scopes.order(:id).map(&:attributes)).to eq(scopes)
  end

  it 'detects a removed scope-completeness trigger even when columns and checks remain present' do
    require Rails.root.join('db/migrate/20261122120000_create_contact_center_pause_approval_evidence')
    review
    expect do
      described_class.transaction(requires_new: true) do
        connection.execute('DROP TRIGGER cc_pause_approval_scope_complete ON jrc_contact_center_pause_approval_scopes')
        CreateContactCenterPauseApprovalEvidence.new.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected pause approval evidence schema/)
    expect(review.scopes.count).to eq(2)
  end

  it 'uses only controlled account/root cascades rather than live actor or canonical-parent foreign keys that alter user lifecycle' do
    roots = connection.foreign_keys(:jrc_contact_center_pause_approval_reviews)
    scopes = connection.foreign_keys(:jrc_contact_center_pause_approval_scopes)
    expect(roots.map(&:to_table)).to eq(['accounts'])
    expect(roots.first.on_delete).to eq(:cascade)
    expect(scopes.map(&:to_table).sort).to eq(%w[accounts jrc_contact_center_pause_approval_reviews])
    expect(scopes.map(&:on_delete)).to all(eq(:cascade))
    expect(connection.columns(:jrc_contact_center_pause_approval_reviews).map(&:name)).not_to include('updated_at')
  end
end

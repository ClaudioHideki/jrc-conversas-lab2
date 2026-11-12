require 'rails_helper'
require Rails.root.join('db/migrate/20261019120000_create_reviewed_relationship_batches')
require Rails.root.join('db/migrate/20261019130000_create_reviewed_relationship_cadences')
require Rails.root.join('db/migrate/20261019140000_add_flow_domain_results')
require Rails.root.join('db/migrate/20261101210000_add_relationship_action_follow_up')
require Rails.root.join('db/migrate/20261101220000_create_relationship_customer_documents')
require Rails.root.join('db/migrate/20261101230000_create_relationship_processing_runs')
require Rails.root.join('db/migrate/20261106113000_add_named_relationship_portfolio_groups')
require Rails.root.join('db/migrate/20261109191000_create_portfolio_history_receipts')
require Rails.root.join('db/migrate/20261109212000_create_relationship_management_requests')

RSpec.describe 'Reviewed operations reversible PostgreSQL upgrade' do
  self.use_transactional_tests = false

  it 'reverses newer dependencies first and reapplies the reviewed migrations without changing native account and conversation data' do
    allowed = %w[jrc_jornada_candidate_test jrc_nico_broker_candidate_test]
    raise 'Disposable database required' unless Rails.env.test? && ENV['JRC_REVIEWED_CONCURRENCY'] == '1' && allowed.include?(ENV['POSTGRES_DATABASE'])

    connection = ActiveRecord::Base.connection
    Account.transaction do
      connection.execute("SET LOCAL lock_timeout='3s'")
      account = create(:account)
      conversation = create(:conversation, account: account)
      original = conversation.reload.attributes
      counts = [Account.count, Contact.count, Conversation.count, Message.count]
      # A real rollback reverses later migrations before dropping the shared
      # assignment index. Keep the cross-account document foreign key intact.
      newer = [AddRelationshipActionFollowUp, CreateRelationshipCustomerDocuments, CreateRelationshipProcessingRuns,
               AddNamedRelationshipPortfolioGroups, CreatePortfolioHistoryReceipts, CreateRelationshipManagementRequests]
      newer.reverse_each { |migration| migration.new.migrate(:down) }
      AddFlowDomainResults.new.down
      CreateReviewedRelationshipCadences.new.down
      CreateReviewedRelationshipBatches.new.down
      expect(connection.table_exists?('jrc_relationship_batch_reviews')).to be(false)
      expect(connection.table_exists?('jrc_relationship_cadence_enrollments')).to be(false)
      CreateReviewedRelationshipBatches.new.up
      CreateReviewedRelationshipCadences.new.up
      AddFlowDomainResults.new.up
      newer.each { |migration| migration.new.migrate(:up) }
      expect([Account.count, Contact.count, Conversation.count, Message.count]).to eq(counts)
      expect(conversation.reload.attributes).to eq(original)
      functions = connection.select_values("SELECT proname FROM pg_proc WHERE proname IN ('rel_batch_review_guard','rel_batch_item_guard','rel_cadence_guard','rel_cadence_step_guard')")
      expect(functions.sort).to eq(%w[rel_batch_item_guard rel_batch_review_guard rel_cadence_guard rel_cadence_step_guard])
      expect(connection.foreign_key_exists?(:jrc_relationship_customer_documents, name: 'rel_document_assignment_tenant')).to be(true)
      expect(connection.column_exists?(:jrc_relationship_actions, :return_at)).to be(true)
      expect(connection.table_exists?(:jrc_relationship_processing_runs)).to be(true)
      raise ActiveRecord::Rollback
    end
  ensure
    ActiveRecord::Base.connection.schema_cache.clear!
  end
end

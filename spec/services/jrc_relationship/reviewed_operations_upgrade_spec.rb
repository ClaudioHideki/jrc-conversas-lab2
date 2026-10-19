require 'rails_helper'
require Rails.root.join('db/migrate/20261019120000_create_reviewed_relationship_batches')
require Rails.root.join('db/migrate/20261019130000_create_reviewed_relationship_cadences')
require Rails.root.join('db/migrate/20261019140000_add_flow_domain_results')

RSpec.describe 'Reviewed operations reversible PostgreSQL upgrade' do
  self.use_transactional_tests = false

  it 'reverses and reapplies all three candidate migrations without changing native account and conversation data' do
    allowed = %w[jrc_jornada_candidate_test jrc_nico_broker_candidate_test]
    raise 'Disposable database required' unless Rails.env.test? && ENV['JRC_REVIEWED_CONCURRENCY'] == '1' && allowed.include?(ENV['POSTGRES_DATABASE'])

    connection = ActiveRecord::Base.connection
    Account.transaction do
      connection.execute("SET LOCAL lock_timeout='3s'")
      account = create(:account)
      conversation = create(:conversation, account: account)
      original = conversation.reload.attributes
      counts = [Account.count, Contact.count, Conversation.count, Message.count]
      AddFlowDomainResults.new.down
      CreateReviewedRelationshipCadences.new.down
      CreateReviewedRelationshipBatches.new.down
      expect(connection.table_exists?('jrc_relationship_batch_reviews')).to be(false)
      expect(connection.table_exists?('jrc_relationship_cadence_enrollments')).to be(false)
      CreateReviewedRelationshipBatches.new.up
      CreateReviewedRelationshipCadences.new.up
      AddFlowDomainResults.new.up
      expect([Account.count, Contact.count, Conversation.count, Message.count]).to eq(counts)
      expect(conversation.reload.attributes).to eq(original)
      functions = connection.select_values("SELECT proname FROM pg_proc WHERE proname IN ('rel_batch_review_guard','rel_batch_item_guard','rel_cadence_guard','rel_cadence_step_guard')")
      expect(functions.sort).to eq(%w[rel_batch_item_guard rel_batch_review_guard rel_cadence_guard rel_cadence_step_guard])
      raise ActiveRecord::Rollback
    end
  ensure
    ActiveRecord::Base.connection.schema_cache.clear!
  end
end

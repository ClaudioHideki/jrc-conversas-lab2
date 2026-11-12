require 'rails_helper'
require 'timeout'

RSpec.describe JrcRelationship::AutomaticActionBudget do
  self.use_transactional_tests = false

  before do
    unless Rails.env.test? && ActiveRecord::Base.connection.select_value('SELECT current_database()') == 'jrc_rel_v2_candidate_test'
      raise 'Use only the owned isolated relationship candidate database'
    end
  end

  # Only new synthetic records in the owned database; retained after the test.
  it 'admits only one concurrent new action into the last daily slot across different customers' do
    account = create(:account)
    account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    owner = create(:user, account: account, role: :administrator)
    rows = Array.new(2) { JrcRelationship::Assignment.create!(account: account, owner: owner, contact: create(:contact, account: account)) }
    JrcRelationship::Configuration.create!(account: account, rules: { automatic_action_daily_limit: 1 })
    gate = Queue.new
    results = Queue.new
    workers = rows.map do |row|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          member = account.account_users.find_by!(user: owner)
          context = JrcRelationship::Context.new(member)
          processor = JrcRelationship::Processor.new(context: context, assignment: row)
          data = { health: { score: 30, band: 'critical' }, days_without_contact: 30, _source_ids: {} }
          result = row.with_lock { processor.action!('health', 'Synthetic concurrent alert', data, context.configuration.effective_rules) }
          results << [result ? :created : :limited, row.id]
        rescue ActiveRecord::LockWaitTimeout
          results << [:retry_after_configuration_contention, row.id]
        rescue StandardError => e
          results << [e.class.name, row.id]
        end
      end
    end
    2.times { gate << true }
    Timeout.timeout(30) { workers.each(&:join) }
    settled = Array.new(2) { results.pop }.map do |state, row_id|
      next state unless state == :retry_after_configuration_contention

      # Native routing fails fast under configuration contention. Retry once,
      # after both transactions finished, rather than pretending it was admitted.
      row = JrcRelationship::Assignment.find(row_id)
      context = JrcRelationship::Context.new(account.account_users.find_by!(user: owner))
      processor = JrcRelationship::Processor.new(context: context, assignment: row)
      data = { health: { score: 30, band: 'critical' }, days_without_contact: 30, _source_ids: {} }
      result = row.with_lock { processor.action!('health', 'Synthetic concurrent alert', data, context.configuration.effective_rules) }
      result ? :unexpected_creation : :limited
    end
    expect(settled).to contain_exactly(:created, :limited)
    expect(JrcRelationship::Action.where(account: account).count).to eq(1)
  ensure
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end
end

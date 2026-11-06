require 'rails_helper'
require 'timeout'

RSpec.describe JrcRelationship::AutomaticPlaybookBudget do
  self.use_transactional_tests = false

  before do
    unless Rails.env.test? && ActiveRecord::Base.connection.select_value('SELECT current_database()') == 'jrc_rel_v2_candidate_test'
      raise 'Use only the owned isolated relationship candidate database'
    end
  end

  # Newly created synthetic records are retained; existing records are never removed.
  it 'admits only one concurrent two-action plan across different customers into the two remaining account slots' do
    account = create(:account)
    account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    actor = create(:user, account: account, role: :administrator)
    rows = Array.new(2) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
    JrcRelationship::Configuration.create!(account: account, rules: { automatic_action_daily_limit: 2, portfolio_capacity_limits: [
                                             { user_id: actor.id, maximum: 10, availability: 1, dedication: 1 }
                                           ] })
    book = JrcRelationship::Playbook.create!(account: account, name: 'Concurrent native automatic work', active: true, trigger_kind: 'no_contact',
                                             steps: [{ 'kind' => 'action', 'title' => 'First real follow-up', 'after_days' => 0 },
                                                     { 'kind' => 'action', 'title' => 'Second real follow-up', 'after_days' => 0 }])
    gate = Queue.new
    results = Queue.new
    workers = rows.map do |row|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          member = account.account_users.find_by!(user: actor)
          context = JrcRelationship::Context.new(member)
          JrcRelationship::AutomaticPlaybooks.new(context).run!(row, 'no_contact', source_key: 'concurrent', playbook_id: book.id)
          results << row.actions.count
        rescue StandardError => e
          results << e.class.name
        end
      end
    end
    2.times { gate << true }
    Timeout.timeout(30) { workers.each(&:join) }
    expect(Array.new(2) { results.pop }).to contain_exactly(0, 2)
    expect(JrcRelationship::Action.where(account: account).count).to eq(2)
    expect(JrcRelationship::PlaybookExecution.where(account: account).count).to eq(1)
  ensure
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end
end

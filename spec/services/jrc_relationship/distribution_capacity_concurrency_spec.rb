require 'rails_helper'
require 'timeout'

RSpec.describe JrcRelationship::DistributionCapacity do
  self.use_transactional_tests = false

  before do
    unless Rails.env.test? && ActiveRecord::Base.connection.select_value('SELECT current_database()') == 'jrc_rel_v2_candidate_test'
      raise 'Use only the owned isolated relationship candidate database'
    end
  end

  # Unique synthetic fixtures are retained in the isolated candidate. No existing
  # fixture, account, container or server is removed or reconfigured by this test.
  it 'admits only one concurrent allocation into the last available customer slot' do
    account = create(:account)
    account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    owner = create(:user, account: account, role: :administrator)
    target = create(:user, account: account, role: :agent)
    rows = Array.new(2) { JrcRelationship::Assignment.create!(account: account, owner: owner, contact: create(:contact, account: account)) }
    JrcRelationship::Configuration.create!(account: account, rules: { portfolio_capacity_limits: [
                                             { user_id: owner.id, maximum: 100, availability: 1, dedication: 1 },
                                             { user_id: target.id, maximum: 1, availability: 1, dedication: 1 }
                                           ] })
    gate = Queue.new
    results = Queue.new
    workers = rows.map do |row|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          JrcRelationship::Assignment.find(row.id).update!(owner_id: target.id)
          results << :applied
        rescue ActiveRecord::RecordInvalid => e
          results << e.record.errors.details.fetch(:owner).first.fetch(:error)
        rescue StandardError => e
          results << e.class.name
        end
      end
    end
    2.times { gate << true }
    Timeout.timeout(30) { workers.each(&:join) }
    expect(Array.new(2) { results.pop }).to contain_exactly(:applied, :portfolio_capacity_exceeded)
    expect(JrcRelationship::Assignment.where(account: account, owner: target).count).to eq(1)
    expect(JrcRelationship::Assignment.where(account: account, owner: owner).count).to eq(1)
  ensure
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end
end

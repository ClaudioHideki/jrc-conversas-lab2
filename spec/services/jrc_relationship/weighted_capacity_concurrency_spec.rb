require 'rails_helper'

RSpec.describe JrcRelationship::WeightedCapacity do
  self.use_transactional_tests = false

  it 'admits only one concurrent allocation into the last available hours slot' do
    raise 'Owned synthetic database only' unless Rails.env.test? && ENV['POSTGRES_DATABASE'] == 'jrc_rel_v2_candidate_test'

    account = create(:account)
    account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    source = create(:user, account: account, role: :administrator)
    target = create(:user, account: account, role: :agent)
    rows = Array.new(2) do
      JrcRelationship::Assignment.create!(account: account, owner: source, contact: create(:contact, account: account),
                                          settings: { 'capacity_workload' => { 'hours' => 1 } })
    end
    JrcRelationship::Configuration.create!(account: account, rules: { portfolio_capacity_limits: [
                                             { user_id: source.id, maximum: 100, availability: 1, dedication: 1 },
                                             { user_id: target.id, maximum: 1.5, availability: 1, dedication: 1, unit: 'hours' }
                                           ] })
    start = Queue.new
    results = Queue.new
    threads = rows.map do |row|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          start.pop
          connection.transaction do
            connection.execute("SET LOCAL lock_timeout = '10s'")
            JrcRelationship::Assignment.find(row.id).update!(owner_id: target.id)
          end
          results << :applied
        rescue ActiveRecord::RecordInvalid => e
          results << e.record.errors.details.fetch(:owner).first.fetch(:error)
        end
      end
    end
    2.times { start << true }
    threads.each(&:value)
    expect(Array.new(2) { results.pop }).to contain_exactly(:applied, :portfolio_capacity_exceeded)
    expect(JrcRelationship::Assignment.where(account: account, owner: target).count).to eq(1)
  end
end

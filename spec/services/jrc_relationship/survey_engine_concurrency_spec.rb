require 'rails_helper'
require 'timeout'

RSpec.describe JrcRelationship::SurveyEngine, :sd_concurrency do
  self.use_transactional_tests = false
  include_context 'JRC Service Desk domain'
  let(:definition) do
    JrcRelationship::SurveyDefinition.create!(
      account: sd_account, name: 'Concurrent NPS', code: 'concurrent_nps', kind: 'nps', status: 'active',
      questions: [{ 'key' => 'rating', 'text' => 'Recommendation?', 'type' => 'scale', 'min' => 0, 'max' => 10, 'required' => true }]
    )
  end
  let(:rule) do
    JrcRelationship::SurveyRule.create!(
      account: sd_account, name: 'Concurrent closure', definition: definition, execution_member: sd_account_user,
      active: true, matchers: { 'source_type' => 'Conversation' }, settings: { 'channel' => 'public_link', 'frequency_days' => 30 }
    )
  end
  let(:conversation) { create(:conversation, account: sd_account, contact: sd_contact, assignee: sd_user, status: :resolved) }

  around do |example|
    database = ENV.fetch('POSTGRES_DATABASE', nil)
    if ENV['JRC_SD_CONCURRENCY'] == '1' && Rails.env.test? && %w[jrc_rel_sd_candidate_test jrc_rel_sd_r2_concurrency_test jrc_rel_sd_r345_concurrency_test].include?(database)
      example.run
    else
      skip 'Requires the explicit disposable candidate PostgreSQL database'
    end
  end

  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_relationship')
    sd_contact.update!(custom_attributes: { 'survey_consent' => true })
    JrcRelationship::Configuration.create!(account: sd_account, rules: { 'survey_automation_enabled' => true })
    rule
    conversation
  end

  def simultaneous(cycles)
    raise 'Fixtures must be committed' if ActiveRecord::Base.connection.transaction_open?

    source_id = conversation.id
    gate = Queue.new
    results = Queue.new
    workers = cycles.map do |cycle|
      Thread.new { evaluate_cycle(source_id, cycle, gate, results) }
    end
    cycles.length.times { gate << true }
    Timeout.timeout(30) { workers.each(&:join) }
    Array.new(cycles.length) { results.pop }
  ensure
    stop_workers(workers)
  end

  def stop_workers(workers)
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end

  def evaluate_cycle(source_id, cycle, gate, results)
    ActiveRecord::Base.connection_pool.with_connection do
      gate.pop
      decision = described_class.evaluate_closure(source: Conversation.find(source_id), cycle_key: cycle)
      results << { id: decision.id, state: decision.state, reason: decision.reason, survey_id: decision.survey_id }
    rescue StandardError => e
      results << e
    end
  end

  it 'creates one decision and one survey for simultaneous retries of the same closure' do
    outcomes = simultaneous(%w[same-cycle same-cycle])
    expect(outcomes).to all(be_a(Hash))
    expect(outcomes.map { |row| row[:id] }.uniq.length).to eq(1)
    expect(outcomes.map { |row| row[:state] }.uniq).to eq(['scheduled'])
    expect(JrcRelationship::Survey.where(account: sd_account).count).to eq(1)
    expect(JrcRelationship::SurveyDispatchDecision.where(account: sd_account, rule: rule).count).to eq(1)
  end

  it 'serializes frequency across simultaneous distinct closure cycles without a second survey' do
    outcomes = simultaneous(%w[first-cycle second-cycle])
    expect(outcomes).to all(be_a(Hash))
    expect(outcomes.map { |row| row[:state] }.sort).to eq(%w[scheduled skipped])
    expect(outcomes.find { |row| row[:state] == 'skipped' }[:reason]).to eq('frequency_exceeded')
    expect(JrcRelationship::Survey.where(account: sd_account).count).to eq(1)
    expect(JrcRelationship::SurveyDispatchDecision.where(account: sd_account, rule: rule).count).to eq(2)
  end
end

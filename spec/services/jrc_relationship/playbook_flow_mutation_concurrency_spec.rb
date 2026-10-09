require 'rails_helper'
require 'timeout'

RSpec.describe JrcRelationship::PlaybookFlowMutationJournal, :sd_concurrency do
  self.use_transactional_tests = false
  include_context 'with a published relationship Flow'

  context 'with the published native Flow fixture' do
    let(:policy) { super().merge('phase' => 3, 'approved_phase' => 3, 'allowed_effects' => %w[contact_update create_lead activity note]) }
    let(:node_definitions) do
      [['start', {}], ['contact', { 'field' => 'name', 'value' => 'One committed phase three mutation' }],
       ['create_lead', {}], ['activity', { 'title' => 'One native concurrent activity', 'user_id' => sd_user.id }],
       ['delay', { 'seconds' => 5 }], ['note', { 'text' => 'One native concurrent continuation' }], ['end', {}]]
    end

    around do |example|
      databases = %w[jrc_rel_sd_candidate_test jrc_rel_sd_r2_concurrency_test jrc_rel_sd_r345_concurrency_test]
      if ENV['JRC_SD_CONCURRENCY'] == '1' && Rails.env.test? && databases.include?(ENV.fetch('POSTGRES_DATABASE', nil))
        example.run
      else
        skip 'Requires the explicit disposable candidate PostgreSQL database'
      end
    end

    def race(&operation)
      raise 'Concurrency fixtures must be committed' if ActiveRecord::Base.connection.transaction_open?

      gate = Queue.new
      results = Queue.new
      workers = Array.new(2) { Thread.new { race_operation(gate, results, &operation) } }
      2.times { gate << true }
      Timeout.timeout(30) { workers.each(&:join) }
      Array.new(2) { results.pop }
    ensure
      workers&.each { |worker| worker.kill if worker.alive? }
      workers&.each(&:join)
    end

    def race_operation(gate, results)
      ActiveRecord::Base.connection_pool.with_connection do
        gate.pop
        results << yield
      rescue StandardError => e
        results << e
      end
    end

    it 'serializes duplicate reviewed admission into one native mutation chain and one pair of CRM records' do
      execution
      approval = review.deep_dup
      outcomes = race do
        fresh = JrcRelationship::PlaybookFlow.new(JrcRelationship::Context.new(AccountUser.find(sd_account_user.id)))
        fresh.call(assignment: JrcRelationship::Assignment.find(assignment.id), step: step, source_key: source_key,
                   execution: JrcRelationship::PlaybookExecution.find(execution.id),
                   payload_digest: approval.fetch('payload_digest'), approval_token: approval.fetch('approval_token'))
      end
      expect(outcomes).to all(be_a(Hash))
      expect(outcomes.map { |row| row.fetch('flow_run_id') }.uniq.size).to eq(1)
      run = JrcFlowRun.find(outcomes.first.fetch('flow_run_id'))
      expect(run.status).to eq('delayed')
      expect(JrcFlowRun.where(account: sd_account).count).to eq(1)
      expect(JrcCrm::Lead.where(conversation: conversation).count).to eq(1)
      expect(JrcCrm::Activity.where(conversation: conversation).count).to eq(1)
      expect(run.settings.fetch(described_class::KEY).fetch('records').map { |row| row['type'] }).to eq(%w[contact create_lead activity])
    end

    it 'serializes simultaneous wakes after own native mutations without a second private effect' do
      run = start_continuation
      version = run.wake_version
      outcomes = travel_to(run.wake_at, with_usec: true) do
        race { JrcFlows::Runner.new(JrcFlowRun.find(run.id)).perform(wake_version: version).status }
      end
      expect(outcomes).to eq(%w[completed completed])
      expect(flow_messages(run).map(&:content)).to eq(['One native concurrent continuation'])
      expect(JrcCrm::Lead.where(conversation: conversation).count).to eq(1)
      expect(JrcCrm::Activity.where(conversation: conversation).count).to eq(1)
      expect(run.reload.settings.fetch(described_class::KEY).fetch('records').size).to eq(3)
    end
  end
end

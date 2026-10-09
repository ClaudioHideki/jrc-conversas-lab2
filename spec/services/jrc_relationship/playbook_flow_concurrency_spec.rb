require 'rails_helper'
require 'timeout'

RSpec.describe JrcRelationship::PlaybookFlow, :sd_concurrency do
  self.use_transactional_tests = false
  include_context 'with a published relationship Flow'

  around do |example|
    database_allowed = %w[jrc_rel_sd_candidate_test jrc_rel_sd_r2_concurrency_test jrc_rel_sd_r345_concurrency_test].include?(ENV.fetch('POSTGRES_DATABASE', nil))
    if ENV['JRC_SD_CONCURRENCY'] == '1' && Rails.env.test? && database_allowed
      example.run
    else
      skip 'Requires the explicit disposable candidate PostgreSQL database'
    end
  end

  def simultaneous(items = [nil, nil], &operation)
    raise 'Concurrency fixtures must be committed' if ActiveRecord::Base.connection.transaction_open?

    gate = Queue.new
    results = Queue.new
    workers = items.map { |item| Thread.new { concurrent_operation(gate, results, operation, item) } }
    2.times { gate << true }
    Timeout.timeout(30) { workers.each(&:join) }
    Array.new(2) { results.pop }
  ensure
    cleanup_workers(workers)
  end

  def cleanup_workers(workers)
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end

  def concurrent_operation(gate, results, operation, item)
    ActiveRecord::Base.connection_pool.with_connection do
      gate.pop
      results << operation.call(item)
    rescue StandardError => e
      results << e
    end
  end

  it 'claims one real native run for simultaneous retries of the same approved origin' do
    execution
    outcomes = simultaneous do
      fresh = described_class.new(JrcRelationship::Context.new(AccountUser.find(sd_account_user.id)))
      fresh.call(assignment: JrcRelationship::Assignment.find(assignment.id), step: step, source_key: source_key,
                 payload_digest: review.fetch('payload_digest'), execution: execution, approval_token: review.fetch('approval_token'))
    end
    expect(outcomes).to all(be_a(Hash))
    expect(outcomes.map { |row| row['flow_run_id'] }.uniq.length).to eq(1)
    expect(JrcFlowRun.where(account: sd_account).count).to eq(1)
  end

  it 'serializes duplicate incoming retries without a second native effect' do
    run = wake_continuation(start_continuation)
    message = client_reply
    outcomes = simultaneous { JrcFlows::Runner.new(JrcFlowRun.find(run.id)).perform(message: Message.find(message.id)).status }
    expect(outcomes).to eq(%w[completed completed])
    expect(flow_messages(run).length).to eq(1)
    expect(run.reload.last_message_id).to eq(message.id)
  end

  it 'serializes the actual timeout and incoming race into one published native path' do
    run = wake_continuation(start_continuation)
    message = client_reply
    outcomes = travel_to(run.wake_at, with_usec: true) do
      simultaneous(%i[timer message]) do |kind|
        runner = JrcFlows::Runner.new(JrcFlowRun.find(run.id))
        kind == :timer ? runner.perform(wake_version: run.wake_version).status : runner.perform(message: Message.find(message.id)).status
      end
    end
    expect(outcomes).to eq(%w[completed completed])
    expect(flow_messages(run).length).to eq(run.reload.variables.key?('reply') ? 1 : 0)
  end

  context 'with an account admission limit across explicit assignments' do
    let(:node_definitions) { [['start', {}], ['note', { 'text' => 'Reviewed bounded native note' }], ['end', {}]] }

    before { policy['hourly_limit'] = 1 }

    it 'serializes account admission before two different assignments can exceed the quota' do
      execution
      other_assignment = JrcRelationship::Assignment.create!(account: sd_account, company: company, owner: sd_user)
      other_source = 'published-second-assignment-source'
      other_review = adapter.preview(assignment: other_assignment, step: step, source_key: other_source, playbook: book)
      other_execution = JrcRelationship::PlaybookExecution.create!(account: sd_account, assignment: other_assignment, playbook: book, actor: sd_user,
                                                                   version: book.version, source_key: other_source,
                                                                   execution_key: Digest::SHA256.hexdigest(other_source), snapshot: book.snapshot,
                                                                   step_source_keys: [other_source])
      inputs = [[assignment, source_key, review, execution], [other_assignment, other_source, other_review, other_execution]]
      outcomes = simultaneous(inputs) do |item|
        selected, source, preview, native_origin = item
        described_class.new(JrcRelationship::Context.new(AccountUser.find(sd_account_user.id)))
                       .call(assignment: selected, step: step, source_key: source, payload_digest: preview.fetch('payload_digest'),
                             execution: native_origin, approval_token: preview.fetch('approval_token'))
      end
      expect(outcomes).to all(be_a(Hash))
      expect(outcomes.map { |row| row['state'] }.sort).to eq(%w[blocked completed])
      expect(outcomes.find { |row| row['state'] == 'blocked' }['reason']).to eq('playbook_flow_hourly_limit')
      expect(JrcFlowRun.where(account: sd_account).count).to eq(1)
      expect(conversation.messages.where(private: true).count).to eq(1)
    end
  end

  context 'with a customer message effect' do
    let(:node_definitions) { [['start', {}], ['message', { 'text' => 'Approved concurrent native message' }], ['end', {}]] }

    it 'commits one dispatch claim before simultaneous provider callbacks' do
      run = start_continuation
      message = flow_messages(run).fetch(0)
      provider_attempts = Queue.new
      outcomes = simultaneous { JrcFlows::Delivery.new(Message.find(message.id)).perform { provider_attempts << message.id } }
      expect(outcomes.grep(Exception)).to be_empty
      expect(provider_attempts.size).to eq(1)
      expect(message.reload.content_attributes['jrc_flow_delivery']).to eq('channel_processed')
    end
  end
end

require 'rails_helper'
require 'sidekiq/api'
require 'sidekiq/testing'

# Prepared actual Redis and committed PostgreSQL cases. Explicit fault
# injection is confined to enqueue, not source/destination access or effects.
# perform_now exercises the native job; it does not prove a Sidekiq dequeue.
RSpec.describe 'Typed ending delivery after actual commit' do
  self.use_transactional_tests = false
  include_context 'with native typed ending schema evidence'

  let(:owned_queue) { "jrc_cc_typed_txn_#{SecureRandom.hex(12)}" }
  let(:native_queue) { Sidekiq::Queue.new(JrcContactCenter::EndingDestinationJob.new.queue_name) }

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned disposable typed delivery probe required' unless owned && !ApplicationRecord.connection.transaction_open?

    identity = Sidekiq.redis { |client| client.call('CLIENT', 'INFO') }
    raise 'Unexpected typed delivery Redis database' unless identity.split.include?('db=15')

    previous_adapter = JrcContactCenter::EndingDestinationJob.queue_adapter
    previous_test_adapter = JrcContactCenter::EndingDestinationJob._test_adapter
    previous_queue = JrcContactCenter::EndingDestinationJob.queue_name
    JrcContactCenter::EndingDestinationJob.queue_adapter = :sidekiq
    JrcContactCenter::EndingDestinationJob.queue_as owned_queue
    raise 'Unexpected typed delivery queue' unless JrcContactCenter::EndingDestinationJob.new.queue_name.end_with?(owned_queue)

    Sidekiq::Testing.disable! { example.run }
  ensure
    JrcContactCenter::EndingDestinationJob.queue_adapter = previous_adapter if previous_adapter
    JrcContactCenter::EndingDestinationJob.enable_test_adapter(previous_test_adapter) if previous_adapter
    JrcContactCenter::EndingDestinationJob.queue_name = previous_queue if previous_queue
  end

  before do
    job = JrcContactCenter::EndingDestinationJob
    job.disable_test_adapter
    job.queue_adapter = :sidekiq
    raise 'Actual typed Sidekiq adapter required' unless job.queue_adapter.is_a?(ActiveJob::QueueAdapters::SidekiqAdapter)
  end

  it 'enqueues only the exact committed attempt after the surrounding transaction ends' do
    identifier = nil
    ApplicationRecord.transaction do
      row = typed_attempt(consent: typed_consent)
      identifier = row.id
      expect(row).to be_persisted
      expect(native_queue.size).to eq(0)
    end
    expect(native_queue.size).to eq(1)
    expect(native_queue.first.item.dig('args', 0, 'job_class')).to eq('JrcContactCenter::EndingDestinationJob')
    expect(native_queue.first.item.dig('args', 0, 'arguments')).to eq([account.id, identifier])
    expect(JrcProjects::Task.where(account: account)).to be_empty
    expect(JrcContactCenter::EndingDestinationOutcome.where(account: account)).to be_empty
  end

  it 'does not leave a typed attempt or Redis delivery after rollback' do
    ApplicationRecord.transaction do
      expect(typed_attempt(consent: typed_consent)).to be_persisted
      raise ActiveRecord::Rollback
    end
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: account)).to be_empty
    expect(native_queue.size).to eq(0)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'does not deliver a rolled-back savepoint when its outer transaction commits' do
    ApplicationRecord.transaction do
      ApplicationRecord.transaction(requires_new: true) do
        expect(typed_attempt(consent: typed_consent)).to be_persisted
        raise ActiveRecord::Rollback
      end
      expect(JrcContactCenter::EndingDestinationAttempt.where(account: account)).to be_empty
    end
    expect(native_queue.size).to eq(0)
  end

  it 'preserves committed work after an explicitly injected known enqueue outage and recovers it natively' do
    allow(JrcContactCenter::EndingDestinationJob).to receive(:perform_later).and_raise(Redis::CannotConnectError, 'SYNTHETIC_PRIVATE_TRANSPORT')
    expect(Rails.logger).to receive(:warn).with(satisfy do |message|
      value = JSON.parse(message)
      value.keys.sort == %w[account_id attempt_id error_class event] && value['account_id'] == account.id &&
        value['error_class'] == Redis::CannotConnectError.name && value['event'] == 'ending_destination_delivery_pending'
    end)
    row = typed_attempt(consent: typed_consent)
    expect(row.reload.outcome).to be_nil
    expect(native_queue.size).to eq(0)
    allow(JrcContactCenter::EndingDestinationJob).to receive(:perform_later).and_call_original
    JrcContactCenter::EndingDestinationReconcileJob.perform_now(account.id)
    expect(row.reload.outcome.outcome).to eq('succeeded')
    expect(JrcProjects::Task.where(account: account).count).to eq(1)
  end

  it 'records an aborted enqueue as recoverable work without exposing transport details' do
    allow(JrcContactCenter::EndingDestinationJob).to receive(:perform_later).and_return(false)
    expect(Rails.logger).to receive(:warn).with(satisfy do |message|
      value = JSON.parse(message)
      value.keys.sort == %w[account_id attempt_id error_class event] && value['error_class'] == 'not_enqueued'
    end)
    row = typed_attempt(consent: typed_consent)
    expect(row.reload.outcome).to be_nil
    expect(native_queue.size).to eq(0)
    allow(JrcContactCenter::EndingDestinationJob).to receive(:perform_later).and_call_original
    expect(JrcContactCenter::EndingActions::DispatchDestinationAttempt.call(row)).to be_truthy
    expect(native_queue.first.item.dig('args', 0, 'arguments')).to eq([account.id, row.id])
  end

  it 'does not disguise an unexpected programming error as a known broker failure' do
    row = typed_attempt(consent: typed_consent)
    allow(JrcContactCenter::EndingDestinationJob).to receive(:perform_later).and_raise(ArgumentError, 'SYNTHETIC_INVALID_DISPATCH')
    expect { JrcContactCenter::EndingActions::DispatchDestinationAttempt.call(row) }
      .to raise_error(ArgumentError, 'SYNTHETIC_INVALID_DISPATCH')
    expect(native_queue.size).to eq(1)
    expect(row.reload.outcome).to be_nil
  end

  it 'revalidates current source rights in the actual job and preserves the terminal refusal after regrant' do
    row = typed_attempt(consent: typed_consent)
    account.disable_features!('jrc_contact_center')
    JrcContactCenter::EndingDestinationJob.perform_now(account.id, row.id)
    expect(row.reload.outcome).to have_attributes(outcome: 'blocked', result_code: 'authorization_denied')
    account.enable_features!('jrc_contact_center')
    JrcContactCenter::EndingDestinationReconcileJob.perform_now(account.id)
    expect(row.reload.outcome).to have_attributes(outcome: 'blocked', result_code: 'authorization_denied')
    expect(JrcProjects::Task.where(account: account)).to be_empty
    expect(JrcContactCenter::EndingDestinationOutcome.where(account: account).count).to eq(1)
  end

  it 'acknowledges a terminal native success without delivering or executing it again' do
    row = typed_attempt(consent: typed_consent)
    JrcContactCenter::EndingDestinationJob.perform_now(account.id, row.id)
    first = row.reload.outcome.attributes
    JrcContactCenter::EndingDestinationJob.perform_now(account.id, row.id)
    expect(row.reload.outcome.attributes).to eq(first)
    expect(JrcProjects::Task.where(account: account).count).to eq(1)
    expect(JrcContactCenter::EndingActions::DispatchDestinationAttempt.call(row)).to be(false)
    expect(native_queue.size).to eq(1)
  end

  it 'keeps unfinished destinations blocked after rule deactivation and reactivation during broker delay' do
    row = typed_attempt(consent: typed_consent)
    publish_typed_schema_definition('active' => false)
    publish_typed_schema_definition('active' => true)
    JrcContactCenter::EndingDestinationReconcileJob.perform_now(account.id)
    expect(row.reload.outcome).to have_attributes(outcome: 'blocked', result_code: 'deactivated')
    expect(JrcProjects::Task.where(account: account)).to be_empty
    expect(JrcContactCenter::EndingDestinationOutcome.where(account: account).count).to eq(1)
  end

  it 'does not treat a valid attempt id as authority in a foreign account job' do
    row = typed_attempt(consent: typed_consent)
    foreign = create(:account)
    JrcContactCenter::EndingDestinationJob.perform_now(foreign.id, row.id)
    expect(row.reload.outcome).to be_nil
    expect(JrcContactCenter::EndingDestinationOutcome.where(account: foreign)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: foreign)).to be_empty
  end
end

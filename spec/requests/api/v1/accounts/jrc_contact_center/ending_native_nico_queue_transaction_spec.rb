require 'rails_helper'
require 'sidekiq/api'
require 'sidekiq/testing'

# Prepared regression, not a native approval. Real Redis is restricted to an
# exclusive synthetic queue; no worker consumes a NICO or external-provider job.
RSpec.describe 'Native NICO capture delivery inside an ending destination transaction' do
  self.use_transactional_tests = false
  include_context 'JRC Service Desk domain'

  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'SYNTHETIC NICO transaction company') }
  let(:ticket) { sd_ticket(company_id: company.id) }
  let(:owned_queue) { "jrc_cc_nico_txn_#{SecureRandom.hex(12)}" }
  let(:native_queue) { Sidekiq::Queue.new(JrcNico::Helpdesk::EventJob.new.queue_name) }
  let(:definition) do
    value = JrcNico::Helpdesk::Definition.defaults.merge('unit_ids' => [sd_unit.id], 'company_ids' => [company.id],
                                                         'operator_ids' => [sd_account_user.id])
    value['rules']['R16']['enabled'] = true
    value
  end
  let(:policy) do
    JrcNico::Helpdesk::PolicyVersion.create!(account: sd_account, author: sd_account_user, number: 1, state: 'published', enabled: true,
                                             published_at: Time.current, definition: definition,
                                             digest: JrcNico::Helpdesk::Definition.digest(definition))
  end

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned NICO transaction probe required' unless owned && !ApplicationRecord.connection.transaction_open?

    redis_identity = Sidekiq.redis { |client| client.call('CLIENT', 'INFO') }
    raise 'Unexpected NICO Redis database' unless redis_identity.split.include?('db=15')

    previous_adapter = JrcNico::Helpdesk::EventJob.queue_adapter
    previous_test_adapter = JrcNico::Helpdesk::EventJob._test_adapter
    previous_queue = JrcNico::Helpdesk::EventJob.queue_name
    JrcNico::Helpdesk::EventJob.queue_adapter = :sidekiq
    JrcNico::Helpdesk::EventJob.queue_as owned_queue
    raise 'Unexpected NICO probe queue' unless JrcNico::Helpdesk::EventJob.new.queue_name.end_with?(owned_queue)

    Sidekiq::Testing.disable! { example.run }
    preserve_queue_boundary(example) unless example.exception
  ensure
    JrcNico::Helpdesk::EventJob.queue_adapter = previous_adapter if previous_adapter
    JrcNico::Helpdesk::EventJob.enable_test_adapter(previous_test_adapter) if previous_adapter
    JrcNico::Helpdesk::EventJob.queue_name = previous_queue if previous_queue
  end

  before do
    configure_owned_nico_transport
    sd_as_admin!
    sd_account.update!(custom_attributes: sd_account.custom_attributes.merge('nico_enabled' => true))
    policy
    ticket
  end

  # The native request-test setup enables a TestAdapter override after around
  # starts. Only this owned Job uses real Redis; no provider worker consumes it.
  def configure_owned_nico_transport
    job = JrcNico::Helpdesk::EventJob
    job.disable_test_adapter
    job.queue_adapter = :sidekiq
    raise 'Actual owned NICO Sidekiq adapter required' unless job.queue_adapter.is_a?(ActiveJob::QueueAdapters::SidekiqAdapter)
  end

  def capture_native_event
    result = JrcNico::Helpdesk::Capture.call(ticket: ticket, trigger: 'created', origin_key: 'synthetic-cc-outer-transaction',
                                             member: sd_account_user)
    raise 'Actual published R16 evidence required' unless result.length == 1 && result.first.rule_key == 'R16'

    result.first
  end

  def create_through_native_workflow
    sd_account.enable_features!('jrc_customer_master')
    sd_contact.update!(company: company)
    attributes = sd_create_attributes.merge(company_id: company.id, title: 'SYNTHETIC native workflow queue boundary')
    JrcServiceDesk::CreateTicketWorkflowService.new(user_context: sd_context).call(
      unit_id: sd_unit.id, attributes: attributes, idempotency_key: SecureRandom.uuid, origin_channel: 'manual'
    )
  end

  # MonitorJob deliberately scans all policies in the disposable application.
  # Observe this event's actual deliveries without replacing its native scope or
  # deleting other synthetic evidence left by committed concurrency examples.
  def native_deliveries_for(event)
    native_queue.map { |job| job.item.dig('args', 0, 'arguments') }.count([event.id])
  end

  def native_queue_identity
    source = IO.popen(%w[git rev-parse HEAD], &:read).strip
    actual = Sidekiq.redis { |client| client.call('CLIENT', 'INFO') }
    raise 'Unexpected NICO Redis identity' unless actual.split.include?('db=15') && source == ENV.fetch('GITHUB_SHA')

    { source_sha: source, actual_Redis_database: 15, actual_database: ApplicationRecord.connection.current_database,
      native_backend_pid: ApplicationRecord.connection.raw_connection.backend_pid,
      queue: native_queue.name, account_id: sd_account.id, policy_version_id: policy.id }
  end

  def native_queue_observations
    jobs = native_queue.map do |job|
      raise 'Unexpected job in own NICO queue' unless job.item.dig('args', 0, 'job_class') == 'JrcNico::Helpdesk::EventJob'

      job.item.dig('args', 0, 'arguments')
    end
    { queued_arguments: jobs, native_events: JrcNico::Helpdesk::Event.where(account: sd_account).pluck(:id, :actor_id, :state),
      delivery_intents: JrcNico::Helpdesk::DispatchIntent.where(account: sd_account).pluck(:id, :event_id) }
  end

  def preserve_queue_boundary(example)
    proof = native_queue_identity.merge(native_queue_observations)
    proof.merge!(synthetic: true, source_line: example.metadata.fetch(:line_number),
                 source_spec_sha256: Digest::SHA256.file(__FILE__).hexdigest, worker_or_provider_execution: false,
                 known_transport_faults_are_injected: true)
    nonce = owned_queue.delete_prefix('jrc_cc_nico_txn_')
    raise 'Unexpected NICO proof nonce' unless nonce.match?(/\A[0-9a-f]{24}\z/)

    File.write("/tmp/call-center-ending-nico-queue-#{nonce}.json", JSON.pretty_generate(proof))
  end

  it 'defers an actual Redis delivery until the enclosing transaction commits' do
    identifier = nil
    ApplicationRecord.transaction do
      event = capture_native_event
      identifier = event.id
      expect(event).to be_persisted
      expect(native_queue.size).to eq(0)
    end
    expect(JrcNico::Helpdesk::Event.find(identifier).state).to eq('detected')
    expect(native_queue.size).to eq(1)
    expect(native_queue.first.item.dig('args', 0, 'arguments')).to eq([identifier])
  end

  it 'leaves neither a durable event nor an orphan Redis delivery after the outer transaction rolls back' do
    ApplicationRecord.transaction do
      expect(capture_native_event).to be_persisted
      raise ActiveRecord::Rollback
    end
    expect(JrcNico::Helpdesk::Event.where(account: sd_account)).to be_empty
    expect(native_queue.size).to eq(0)
  end

  it 'does not enqueue an existing detected correlation again when its enclosing retry is rolled back' do
    previous = capture_native_event
    expect(native_queue.size).to eq(1)
    ApplicationRecord.transaction do
      expect(capture_native_event.id).to eq(previous.id)
      raise ActiveRecord::Rollback
    end
    expect(JrcNico::Helpdesk::Event.where(account: sd_account).pluck(:id)).to eq([previous.id])
    expect(native_queue.size).to eq(1)
  end

  it 'does not promote a rolled-back savepoint delivery when the enclosing transaction commits' do
    ApplicationRecord.transaction do
      ApplicationRecord.transaction(requires_new: true) do
        expect(capture_native_event).to be_persisted
        raise ActiveRecord::Rollback
      end
      expect(JrcNico::Helpdesk::Event.where(account: sd_account)).to be_empty
    end
    expect(native_queue.size).to eq(0)
  end

  it 'preserves the native delivery when capture has no enclosing transaction' do
    event = capture_native_event
    expect(JrcNico::Helpdesk::Event.find(event.id).state).to eq('detected')
    expect(native_queue.size).to eq(1)
    expect(native_queue.first.item.dig('args', 0, 'arguments')).to eq([event.id])
  end

  it 'recovers existing detected R16 evidence even though native monitor facts do not redetect creation' do
    event = capture_native_event
    expect(native_deliveries_for(event)).to eq(1)
    travel(1.second) { JrcNico::Helpdesk::MonitorJob.perform_now }
    expect(native_deliveries_for(event)).to eq(2)
    expect(JrcNico::Helpdesk::Event.where(account: sd_account).pluck(:id)).to eq([event.id])
    expect(event.reload.state).to eq('detected')
  end

  it 'retains committed pending evidence after an injected known Redis fault and recovers a real delivery' do
    allow(JrcNico::Helpdesk::EventJob).to receive(:perform_later).and_raise(Redis::CannotConnectError, 'SYNTHETIC_PRIVATE_TRANSPORT_DETAIL')
    expect(Rails.logger).to receive(:warn).with(satisfy do |message|
      value = JSON.parse(message)
      value.keys.sort == %w[account_id error_class event event_id] && value['account_id'] == sd_account.id &&
        value['event'] == 'nico_helpdesk_delivery_pending' && value['error_class'] == Redis::CannotConnectError.name
    end)
    event = capture_native_event
    expect(event.reload.state).to eq('detected')
    expect(native_queue.size).to eq(0)
    allow(JrcNico::Helpdesk::EventJob).to receive(:perform_later).and_call_original
    travel(1.second) { JrcNico::Helpdesk::MonitorJob.perform_now }
    expect(native_deliveries_for(event)).to eq(1)
    expect(event.reload).to have_attributes(policy_version_id: policy.id, actor_id: sd_account_user.id, state: 'detected')
  end

  it 'records a native aborted enqueue as pending rather than silently dropping its evidence' do
    allow(JrcNico::Helpdesk::EventJob).to receive(:perform_later).and_return(false)
    expect(Rails.logger).to receive(:warn).with(satisfy do |message|
      value = JSON.parse(message)
      value.keys.sort == %w[account_id error_class event event_id] && value['account_id'] == sd_account.id &&
        value['event'] == 'nico_helpdesk_delivery_pending' && value['error_class'] == 'not_enqueued'
    end)
    event = capture_native_event
    expect(event.reload.state).to eq('detected')
    expect(native_queue.size).to eq(0)
    allow(JrcNico::Helpdesk::EventJob).to receive(:perform_later).and_call_original
    travel(1.second) { JrcNico::Helpdesk::MonitorJob.perform_now }
    expect(native_deliveries_for(event)).to eq(1)
  end

  it 'does not recover terminal evidence or revive a halted native policy' do
    event = capture_native_event
    JrcNico::Helpdesk::Controls.new(sd_account_user).disable(id: policy.id, reason: 'SYNTHETIC explicit halt', request_key: SecureRandom.uuid)
    JrcNico::Helpdesk::EventProcessor.new(event).call
    expect(event.reload.state).to eq('blocked')
    travel(1.second) { JrcNico::Helpdesk::MonitorJob.perform_now }
    expect(native_deliveries_for(event)).to eq(1)
    expect(event.reload.state).to eq('blocked')
    expect(JrcNico::Helpdesk::PolicyControl.find_by!(policy_version: policy).halted).to be(true)
  end

  it 'commits a real native Ticket workflow and its creation evidence before requesting actual Redis delivery' do
    event = nil
    created = nil
    ApplicationRecord.transaction do
      created = create_through_native_workflow
      event = JrcNico::Helpdesk::Event.where(account: sd_account, ticket: created, rule_key: 'R16').sole
      expect(JrcNico::Helpdesk::DispatchIntent.where(account: sd_account, event: event)).to exist
      expect(native_queue.size).to eq(0)
    end
    expect(created.reload.ticket_events.where(event_type: 'creation_context_recorded')).to exist
    expect(event.reload).to have_attributes(ticket_id: created.id, actor_id: sd_account_user.id, state: 'detected')
    expect(native_queue.first.item.dig('args', 0, 'arguments')).to eq([event.id])
  end

  it 'rolls back native Ticket history and NICO evidence together without an orphan actual Redis delivery' do
    original = JrcServiceDesk::Ticket.where(account: sd_account).pluck(:id)
    created_id = nil
    ApplicationRecord.transaction do
      created_id = create_through_native_workflow.id
      expect(JrcNico::Helpdesk::Event.where(account: sd_account, ticket_id: created_id, rule_key: 'R16')).to exist
      expect(native_queue.size).to eq(0)
      raise ActiveRecord::Rollback
    end
    expect(JrcServiceDesk::Ticket.where(account: sd_account).pluck(:id)).to eq(original)
    expect(JrcServiceDesk::TicketEvent.where(account: sd_account, ticket_id: created_id)).to be_empty
    expect(JrcNico::Helpdesk::Event.where(account: sd_account, ticket_id: created_id)).to be_empty
    expect(JrcNico::Helpdesk::DispatchIntent.where(account: sd_account)).to be_empty
    expect(native_queue.size).to eq(0)
  end

  it 'does not swallow an unexpected programming error as a recoverable Redis outage' do
    event = capture_native_event
    allow(JrcNico::Helpdesk::EventJob).to receive(:perform_later).and_raise(ArgumentError, 'SYNTHETIC_INVALID_DISPATCH')
    expect { JrcNico::Helpdesk::EventDispatch.call(event) }.to raise_error(ArgumentError, 'SYNTHETIC_INVALID_DISPATCH')
    expect(native_deliveries_for(event)).to eq(1)
    expect(event.reload.state).to eq('detected')
  end

  it 'does not backfill or release historical detected evidence without a new native capture request' do
    legacy = JrcNico::Helpdesk::Event.create!(account: sd_account, actor: sd_account_user, ticket: ticket, policy_version: policy,
                                              rule_key: 'R16', correlation_key: "synthetic-legacy:#{SecureRandom.uuid}", detected_at: Time.current)
    snapshot = legacy.attributes.slice('evidence', 'correlation_key', 'detected_at', 'actor_id', 'policy_version_id', 'state')
    expect(JrcNico::Helpdesk::DispatchIntent.where(account: sd_account)).to be_empty
    travel(1.second) { JrcNico::Helpdesk::MonitorJob.perform_now }
    expect(native_deliveries_for(legacy)).to eq(0)
    expect(JrcNico::Helpdesk::DispatchIntent.where(account: sd_account)).to be_empty
    expect(legacy.reload.attributes.slice(*snapshot.keys)).to eq(snapshot)
  end

  it 'does not leak a recovery delivery when a surrounding monitor transaction rolls back' do
    event = capture_native_event
    expect(native_deliveries_for(event)).to eq(1)
    ApplicationRecord.transaction do
      travel(1.second) { JrcNico::Helpdesk::MonitorJob.perform_now }
      expect(native_deliveries_for(event)).to eq(1)
      raise ActiveRecord::Rollback
    end
    expect(native_deliveries_for(event)).to eq(1)
    expect(JrcNico::Helpdesk::DispatchIntent.where(account: sd_account).sole.event_id).to eq(event.id)
  end
end

require 'rails_helper'

RSpec.describe JrcRelationship::PlaybookFlowWebhookDelivery, :sd_concurrency do
  self.use_transactional_tests = false
  include JrcServiceDeskConcurrency
  include_context 'with a published relationship Flow'

  let(:policy) do
    JrcRelationship::PlaybookFlowPolicy::DEFAULTS.deep_dup.merge(
      'phase' => 3, 'approved_phase' => 3, 'allowed_effects' => %w[note webhook], 'pilot_company_ids' => [company.id],
      'pilot_account_user_ids' => [sd_account_user.id], 'allow_unassigned_business_unit' => true
    )
  end
  let(:node_definitions) do
    [['start', {}], ['webhook', { 'url' => 'https://example.com/approved-hook', 'body' => 'Explicit approved value' }],
     ['note', { 'text' => 'Native continuation after receipt' }], ['end', {}]]
  end
  let(:post_request) do
    stub_request(:post, 'https://example.com/approved-hook').to_return(status: 200, body: '{"accepted":true}')
  end

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('example.com').and_return(['93.184.216.34'])
  end

  def webhook_record(run)
    run.reload.settings.fetch(JrcRelationship::PlaybookFlowWebhookJournal::KEY).fetch('records').fetch('node1')
  end

  def deliver_webhook(run)
    JrcRelationship::PlaybookFlowWebhookJob.perform_now(run.id, 'node1')
    run.reload
  end

  it 'previews without POST and commits a queued intent without running the downstream node' do
    post_request
    expect(review['reason']).to be_nil
    expect(post_request).not_to have_been_requested
    run = start_continuation
    expect(run).to have_attributes(status: 'waiting', node_id: 'node1', wake_at: nil)
    expect(webhook_record(run)).to include('state' => 'queued')
    expect(flow_messages(run)).to be_empty
    expect(post_request).not_to have_been_requested
    expect(JrcRelationship::PlaybookFlowWebhookJournal.new(run).verify_integrity!.keys).to eq(['node1'])
  end

  it 'publishes only a queued transport intent after commit and recovers it using the native PostgreSQL JSONB query' do
    post_request
    run = start_continuation
    jobs = enqueued_jobs.select { |job| job[:job] == JrcRelationship::PlaybookFlowWebhookJob && job[:args] == [run.id, 'node1'] }
    expect(jobs.length).to eq(1)
    clear_enqueued_jobs
    expect { JrcFlows::RecoveryJob.perform_now }.not_to(change(Message, :count))
    jobs = enqueued_jobs.select { |job| job[:job] == JrcRelationship::PlaybookFlowWebhookJob && job[:args] == [run.id, 'node1'] }
    expect(jobs.length).to eq(1)
    expect(post_request).not_to have_been_requested
    deliver_webhook(run)
    clear_enqueued_jobs
    JrcFlows::RecoveryJob.perform_now
    expect(enqueued_jobs.select { |job| job[:job] == JrcRelationship::PlaybookFlowWebhookJob && job[:args] == [run.id, 'node1'] }).to be_empty
    expect(post_request).to have_been_requested.once
  end

  it 'has a committed dispatch claim visible to another connection before the actual SafeFetch POST' do
    run = start_continuation
    observations = []
    request = stub_request(:post, 'https://example.com/approved-hook').with do |http|
      observations << Timeout.timeout(30) do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            JrcFlowRun.find(run.id).settings.dig(JrcRelationship::PlaybookFlowWebhookJournal::KEY, 'records', 'node1', 'state')
          end
        end.value
      end
      body = JSON.parse(http.body)
      expect(body).to eq('event' => 'jrc.flow', 'flow_id' => flow.id, 'run_id' => run.id,
                        'conversation_id' => conversation.display_id, 'data' => 'Explicit approved value')
      expect(http.headers['Idempotency-Key']).to eq("jrc-flow-#{run.id}-node1")
      true
    end.to_return(status: 200, body: '{"accepted":true}')
    deliver_webhook(run)
    expect(observations).to eq(['dispatching'])
    expect(request).to have_been_requested.once
    expect(webhook_record(run)).to include('state' => 'response_received', 'response_digest' => Digest::SHA256.hexdigest('{"accepted":true}'))
    expect(run.status).to eq('completed')
    expect(flow_messages(run).map(&:content)).to eq(['Native continuation after receipt'])
  end

  it 'replays the same approved origin and duplicate jobs without another POST or downstream message' do
    post_request
    run = start_continuation
    deliver_webhook(run)
    expect(start_continuation.id).to eq(run.id)
    deliver_webhook(run)
    expect(post_request).to have_been_requested.once
    expect(flow_messages(run).length).to eq(1)
    expect(run.status).to eq('completed')
  end

  it 'delivers an already charged node at the exact step limit while refusing a new downstream step' do
    policy['max_steps'] = 2
    post_request
    run = start_continuation
    expect(run).to have_attributes(status: 'waiting', steps: 2, node_id: 'node1')
    deliver_webhook(run)
    expect(post_request).to have_been_requested.once
    expect(webhook_record(run)['state']).to eq('response_received')
    expect(run).to have_attributes(status: 'failed', steps: 2, error: 'playbook_flow_execution_failed')
    expect(flow_messages(run)).to be_empty
    deliver_webhook(run)
    expect(post_request).to have_been_requested.once
  end

  it 'serializes concurrent actual transport jobs into one POST and one native continuation' do
    post_request
    run = start_continuation
    operations = Array.new(2) do
      -> { described_class.new(JrcFlowRun.find(run.id), 'node1').perform }
    end
    outcomes = concurrently(operations)
    expect(outcomes.grep(Exception)).to be_empty
    expect(post_request).to have_been_requested.once
    expect(run.reload.status).to eq('completed')
    expect(flow_messages(run).length).to eq(1)
  end

  it 'stops before POST when the original actor loses access' do
    post_request
    run = start_continuation
    sd_membership.update!(active: false)
    deliver_webhook(run)
    expect(post_request).not_to have_been_requested
    expect(run.status).to eq('paused')
    expect(webhook_record(run)['state']).to eq('cancelled')
    expect(flow_messages(run)).to be_empty
  end

  it 'stops before POST when the reviewed approval has expired' do
    post_request
    run = start_continuation
    travel_to(Time.current + policy.fetch('approval_ttl_seconds').seconds + 1.second) { deliver_webhook(run) }
    expect(post_request).not_to have_been_requested
    expect(run.reload.status).to eq('paused')
    expect(webhook_record(run)['state']).to eq('cancelled')
  end

  it 'stops before POST when the published definition has changed' do
    post_request
    run = start_continuation
    flow.update!(name: 'Republished native flow')
    deliver_webhook(run)
    expect(post_request).not_to have_been_requested
    expect(run.status).to eq('paused')
    expect(flow_messages(run)).to be_empty
  end

  it 'stops before POST on an actual human takeover or new incoming reply' do
    post_request
    run = start_continuation
    client_reply
    deliver_webhook(run)
    expect(post_request).not_to have_been_requested
    expect(webhook_record(run)['state']).to eq('cancelled')
    expect(run.status).to eq('paused')
    expect(flow_messages(run)).to be_empty
  end

  it 'permits historical incoming messages without selecting their content as an implicit Flow input' do
    prior = client_reply(content: 'Historical customer text not selected as input')
    post_request
    run = start_continuation
    expect(run.last_message_id).to eq(0)
    expect(run.variables['message']).to eq('')
    expect(webhook_record(run)['incoming_watermark']).to eq(prior.id)
    expect(webhook_record(run).fetch('payload')['data']).to eq('Explicit approved value')
    deliver_webhook(run)
    expect(post_request).to have_been_requested.once
    expect(run.status).to eq('completed')
    expect(flow_messages(run).length).to eq(1)
  end

  it 'marks a transport timeout unknown and never automatically reposts that node' do
    request = stub_request(:post, 'https://example.com/approved-hook').to_timeout
    run = start_continuation
    deliver_webhook(run)
    expect(webhook_record(run)['state']).to eq('unknown')
    expect(run.status).to eq('paused')
    expect(run.error).to eq('playbook_flow_webhook_outcome_unconfirmed')
    deliver_webhook(run)
    JrcRelationship::PlaybookFlowWebhookDelivery.recover(run)
    expect(request).to have_been_requested.once
    expect(flow_messages(run)).to be_empty
  end

  it 'never reposts an already claimed intent after a simulated worker interruption' do
    post_request
    run = start_continuation
    journal = JrcRelationship::PlaybookFlowWebhookJournal.new(run)
    journal.update!('node1', state: 'dispatching', claim: 'native-interrupted-worker', claimed_at: 3.minutes.ago.iso8601(6))
    deliver_webhook(run)
    described_class.recover(run)
    expect(post_request).not_to have_been_requested
    expect(webhook_record(run)['state']).to eq('unknown')
    expect(run.status).to eq('paused')
  end

  it 'does not consume an incoming reply as though the webhook node were an input node' do
    post_request
    run = start_continuation
    JrcFlows::Runner.new(run).perform(message: client_reply)
    expect(run.reload).to have_attributes(status: 'waiting', node_id: 'node1')
    expect(post_request).not_to have_been_requested
    expect(flow_messages(run)).to be_empty
  end

  it 'denies a forged signed intent without exposing or posting its replacement payload' do
    post_request
    run = start_continuation
    journal = run.settings.fetch(JrcRelationship::PlaybookFlowWebhookJournal::KEY).deep_dup
    journal.fetch('records').fetch('node1').fetch('payload')['data'] = 'Foreign replacement'
    run.update!(settings: run.settings.merge(JrcRelationship::PlaybookFlowWebhookJournal::KEY => journal))
    deliver_webhook(run)
    expect(post_request).not_to have_been_requested
    expect(run.status).to eq('paused')
    expect(run.error).to eq('playbook_flow_webhook_authorization_blocked')
    expect(flow_messages(run)).to be_empty
  end

  context 'with a terminal native NICO handoff' do
    let(:policy) { super().merge('allowed_effects' => ['nico']) }
    let(:node_definitions) { [['start', {}], ['nico', { 'objective' => 'Explicit native delegation', 'hours' => 2, 'allowed_actions' => [] }]] }
    let(:publisher) { create(:user) }

    around { |example| with_modified_env(NICO_MODE: 'provider') { example.run } }
    before do
      create(:account_user, account: sd_account, user: publisher, role: :administrator)
      sd_account.update!(custom_attributes: sd_account.custom_attributes.merge('nico_enabled' => true, 'nico_customer_delegation_enabled' => true))
      JrcAi::Provider.create!(account: sd_account, name: 'Synthetic committed provider', provider_type: 'openai', default_model: 'test-model',
                              api_key: 'test-committed-native-flow-key', active: true, default_provider: true)
      flow.update!(created_by: publisher)
      clear_enqueued_jobs
    end

    it 'uses the original actor, commits the terminal handoff, and relies on precisely the two existing delegation scheduling callbacks' do
      run = start_continuation
      expect(run.status).to eq('completed')
      delegation = JrcNico::Delegation.find(run.variables.fetch('delegation_id'))
      expect(delegation.user_id).to eq(sd_user.id)
      expect(delegation.user_id).not_to eq(publisher.id)
      expect(JrcFlowRun.live.where(conversation: conversation)).to be_empty
      jobs = enqueued_jobs.select { |job| job[:job] == JrcNico::CustomerTurnJob && job[:args] == [delegation.id] }
      expect(jobs.length).to eq(2)
      expect(start_continuation.id).to eq(run.id)
      expect(enqueued_jobs.select { |job| job[:job] == JrcNico::CustomerTurnJob && job[:args] == [delegation.id] }.length).to eq(2)
    end
  end

  context 'with a native delayed continuation' do
    let(:policy) { super().merge('allowed_effects' => ['note']) }
    let(:node_definitions) { [['start', {}], ['delay', { 'seconds' => 5 }], ['note', { 'text' => 'After committed native timer' }], ['end', {}]] }

    it 'publishes the native timer intent after admission reload and preserves the exact wake version on replay' do
      clear_enqueued_jobs
      run = start_continuation
      expect(run.status).to eq('delayed')
      jobs = enqueued_jobs.select { |job| job[:job] == JrcRelationship::PlaybookFlowResumeJob && job[:args] == [run.id, run.wake_version] }
      expect(jobs.length).to eq(1)
      expect(jobs.fetch(0)[:at]).to be_within(0.000001).of(run.wake_at.to_f)
      expect(start_continuation.id).to eq(run.id)
      expect(enqueued_jobs.select { |job| job[:job] == JrcRelationship::PlaybookFlowResumeJob && job[:args] == [run.id, run.wake_version] }.length).to eq(1)
      wake_continuation(run)
      expect(run.status).to eq('completed')
      expect(flow_messages(run).map(&:content)).to eq(['After committed native timer'])
    end
  end
end

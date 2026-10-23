require 'rails_helper'
require 'database_cleaner/active_record'
require 'timeout'

# Committed fixtures let Broker callbacks use a genuinely independent PostgreSQL connection.
RSpec.describe JrcCampaigns::ApprovalService do
  self.use_transactional_tests = false
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:origin) { 'https://broker.example.test' }
  let(:integration_id) { SecureRandom.uuid }
  let(:instance_id) { SecureRandom.uuid }
  let(:prefix) { "#{origin}/v1/integrations/chatwoot/control" }
  let(:transport_path) { "#{prefix}/connections/#{integration_id}/campaign-transport" }
  let(:inbox) do
    create(:inbox, account: account, channel: create(:channel_api, account: account,
                                                                   webhook_url: "#{origin}/v1/integrations/chatwoot/#{integration_id}/events"))
  end
  let(:campaign) { JrcCampaigns::Campaign.create!(account: account, inbox: inbox, created_by: admin, name: 'Synthetic preflight') }
  let(:step) { campaign.steps.create!(kind: 'text', body: 'Synthetic text', position: 0) }
  let(:transport) do
    { protocol: 'chatwoot-campaigns/v1', integrationId: integration_id, instanceId: instance_id, inboxId: inbox.id,
      destinationRevision: 1, identityRevision: 2, ownerRevision: 0, numberSuffix: '0000', ready: true, reason: nil }
  end

  around do |example|
    disposable = Rails.env.test? && ActiveRecord::Base.connection.adapter_name == 'PostgreSQL' &&
                 ActiveRecord::Base.connection_db_config.database.end_with?('_test')
    raise 'Disposable PostgreSQL test database required' unless disposable

    DatabaseCleaner.clean_with(:deletion)
    with_modified_env('JRC_BROKER_ENABLED' => 'true', 'JRC_BROKER_ALLOWED_ORIGINS' => origin, 'FRONTEND_URL' => 'https://central.example.test',
                      'JRC_BROKER_CREDENTIAL_KEY' => Base64.strict_encode64('s' * 32)) { example.run }
  ensure
    clear_enqueued_jobs
    DatabaseCleaner.clean_with(:deletion) if disposable
  end

  before do
    account.enable_features!('jrc_broker', 'jrc_campaigns')
    ciphertext = JrcBroker::Configuration.credential_store.encrypt(account_id: account.id, token: 'synthetic-scoped-key')
    integration = JrcBrokerIntegration.create!(account: account, broker_origin: origin, organization_id: SecureRandom.uuid,
                                               destination_revision: 1, encrypted_control_key: ciphertext)
    JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: integration_id, instance_id: instance_id)
    stub_request(:get, "#{prefix}/context").to_return(headers: { 'Content-Type' => 'application/json' }, body: {
      organizationId: integration.organization_id, accountId: account.id, destinationRevision: 1, chatwootOrigin: 'https://central.example.test'
    }.to_json)
    stub_request(:get, transport_path).to_return(headers: { 'Content-Type' => 'application/json' }, body: transport.to_json)
    step
    clear_enqueued_jobs
  end

  it 'performs review identity reads without a transaction or a leased database connection' do
    states = []
    stub_request(:get, transport_path).to_return do
      connection = ActiveRecord::Base.connection_pool.active_connection?
      states << [connection&.transaction_open? == true, connection.present?]
      { headers: { 'Content-Type' => 'application/json' }, body: transport.to_json }
    end
    campaign.request_review!
    expect(states).to eq([[false, false]])
    expect(campaign.review_digest).to be_present
  end

  it 'performs approval identity reads before opening its write transaction' do
    campaign.request_review!
    active_transactions = []
    stub_request(:get, transport_path).to_return do
      active_transactions << ActiveRecord::Base.connection_pool.active_connection?&.transaction_open?
      { headers: { 'Content-Type' => 'application/json' }, body: transport.to_json }
    end
    campaign.approve!(admin, campaign.review_digest)
    expect(active_transactions).to eq([nil])
    expect(campaign.approved_by_id).to eq(admin.id)
  end

  it 'allows a reentrant callback with one PostgreSQL pool slot while the Broker read is pending' do
    original_configuration = ActiveRecord::Base.connection_db_config.configuration_hash
    ActiveRecord::Base.establish_connection(original_configuration.merge(pool: 1, checkout_timeout: 0.5))
    callback_outcome = nil
    stub_request(:get, transport_path).to_return do
      callback = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          JrcCampaigns::Campaign.transaction { JrcCampaigns::Campaign.lock('FOR UPDATE NOWAIT').find(campaign.id) }
          :available
        end
      rescue StandardError => e
        e.class.name
      end
      callback_outcome = Timeout.timeout(5) { callback.value }
      { headers: { 'Content-Type' => 'application/json' }, body: transport.to_json }
    ensure
      callback&.kill if callback&.alive?
      callback&.join
    end
    campaign.request_review!
    expect(callback_outcome).to eq(:available)
  ensure
    ActiveRecord::Base.establish_connection(original_configuration) if original_configuration
  end

  it 'performs launch identity reads outside the campaign lock and retains its fresh remote check' do
    campaign.request_review!
    campaign.approve!(admin, campaign.review_digest)
    active_transactions = []
    stub_request(:get, transport_path).to_return do
      active_transactions << ActiveRecord::Base.connection_pool.active_connection?&.transaction_open?
      { headers: { 'Content-Type' => 'application/json' }, body: transport.to_json }
    end
    campaign.launch!
    expect(active_transactions).to eq([nil])
    expect(campaign.reload).to be_running
  end

  it 'performs execution identity reads outside its write transaction' do
    campaign.request_review!
    campaign.approve!(admin, campaign.review_digest)
    active_transactions = []
    stub_request(:get, transport_path).to_return do
      active_transactions << ActiveRecord::Base.connection_pool.active_connection?&.transaction_open?
      { headers: { 'Content-Type' => 'application/json' }, body: transport.to_json }
    end
    JrcCampaigns::LaunchService.new(campaign).perform
    expect(active_transactions).to eq([nil])
    expect(campaign.executions.count).to eq(1)
  end

  it 'serializes local human approval without fetching remote identity or hiding a persisted status behind a failed read' do
    campaign.request_review!
    campaign.approve!(admin, campaign.review_digest)
    WebMock::RequestRegistry.instance.reset!
    stub_request(:get, transport_path).to_return(status: 503)
    serialized = JrcCampaigns::CampaignSerializer.new(campaign).as_json
    expect(serialized).to include(approval_valid: true)
    expect(a_request(:get, transport_path)).not_to have_been_made
    expect(a_request(:get, "#{prefix}/context")).not_to have_been_made
    expect { campaign.ensure_approved! }.to raise_error(JrcBroker::Client::Error)
  end

  it 'rejects a binding changed during the remote review read without persisting a stale review' do
    stub_request(:get, transport_path).to_return do
      JrcBrokerInboxBinding.find_by!(inbox: inbox).update!(instance_id: SecureRandom.uuid)
      { headers: { 'Content-Type' => 'application/json' }, body: transport.to_json }
    end
    expect { campaign.request_review! }.to raise_error(ActiveRecord::RecordInvalid)
    expect(campaign.reload.review_digest).to be_nil
  end

  it 'rejects a step changed during approval without reusing the old review digest' do
    campaign.request_review!
    stub_request(:get, transport_path).to_return do
      step.update!(body: 'Changed during remote read')
      { headers: { 'Content-Type' => 'application/json' }, body: transport.to_json }
    end
    expect { campaign.approve!(admin, campaign.review_digest) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(campaign.reload.approved_digest).to be_nil
  end

  it 'rejects a callback changed during approval even when the remote identity revision is unchanged' do
    campaign.request_review!
    stub_request(:get, transport_path).to_return do
      inbox.channel.update!(webhook_url: 'https://changed.example.test/events')
      { headers: { 'Content-Type' => 'application/json' }, body: transport.to_json }
    end
    expect { campaign.approve!(admin, campaign.review_digest) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(campaign.reload.approved_digest).to be_nil
  end

  it 'rejects an approver whose administrator role is revoked during the remote read' do
    campaign.request_review!
    stub_request(:get, transport_path).to_return do
      AccountUser.find_by!(account: account, user: admin).update!(role: :agent)
      { headers: { 'Content-Type' => 'application/json' }, body: transport.to_json }
    end
    expect { campaign.approve!(admin, campaign.review_digest) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(campaign.reload.approved_digest).to be_nil
  end

  it 'does not write a new review into a campaign canceled during the remote read' do
    stub_request(:get, transport_path).to_return do
      JrcCampaigns::Campaign.find(campaign.id).cancel!
      { headers: { 'Content-Type' => 'application/json' }, body: transport.to_json }
    end
    expect { campaign.request_review! }.to raise_error(ActiveRecord::RecordInvalid)
    expect(campaign.reload).to be_canceled
    expect(campaign.review_digest).to be_nil
  end

  it 'does not start when the remote sender identity no longer matches the approved review' do
    campaign.request_review!
    campaign.approve!(admin, campaign.review_digest)
    stub_request(:get, transport_path).to_return(headers: { 'Content-Type' => 'application/json' },
                                                 body: transport.merge(identityRevision: 3).to_json)
    expect { campaign.launch! }.to raise_error(ActiveRecord::RecordInvalid)
    expect(campaign.reload).to be_draft
    expect(campaign.executions).to be_empty
  end

  %w[canceled paused].each do |state|
    it "preserves a concurrent #{state} state when the execution preflight fails" do
      campaign.request_review!
      campaign.approve!(admin, campaign.review_digest)
      campaign.update!(status: 'running')
      stub_request(:get, transport_path).to_return do
        current = JrcCampaigns::Campaign.find(campaign.id)
        state == 'canceled' ? current.cancel! : current.pause!
        { status: 503 }
      end
      expect { JrcCampaigns::LaunchService.new(campaign).perform }.to raise_error(JrcBroker::Client::Error)
      expect(campaign.reload.status).to eq(state)
      expect(campaign.executions).to be_empty
    end
  end

  it 'does not release a database connection that already has an explicit transaction' do
    observed = []
    original = nil
    stub_request(:get, "#{prefix}/context").to_return do
      connection = ActiveRecord::Base.connection_pool.active_connection?
      observed << [connection == original, connection&.transaction_open?]
      integration = JrcBrokerIntegration.find_by!(account: account)
      { headers: { 'Content-Type' => 'application/json' }, body: {
        organizationId: integration.organization_id, accountId: account.id, destinationRevision: 1, chatwootOrigin: 'https://central.example.test'
      }.to_json }
    end
    Account.transaction do
      original = ActiveRecord::Base.connection
      JrcBroker::Context.new(account: account, user: admin, release_connection: true)
      expect(ActiveRecord::Base.connection_pool.active_connection?).to eq(original)
    end
    expect(observed).to eq([[true, true]])
  end

  it 'holds source and approver rows through the approval write after validating the remote snapshot' do
    campaign.request_review!
    binding = JrcBrokerInboxBinding.find_by!(inbox: inbox)
    member = AccountUser.find_by!(account: account, user: admin)
    outcomes = []
    allow(campaign).to receive(:update!).and_wrap_original do |original, *args, **kwargs|
      if args.first&.key?(:approved_digest) || kwargs.key?(:approved_digest)
        [binding, member, step, inbox.channel, JrcBrokerIntegration.find_by!(account: account)].each do |source|
          worker = Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              source.class.transaction { source.class.lock('FOR UPDATE NOWAIT').find(source.id) }
              :changed
            end
          rescue StandardError => e
            e.class.name
          end
          outcomes << Timeout.timeout(5) { worker.value }
        ensure
          worker&.kill if worker&.alive?
          worker&.join
        end
      end
      original.call(*args, **kwargs)
    end
    campaign.approve!(admin, campaign.review_digest)
    expect(outcomes).to eq(Array.new(5, 'ActiveRecord::LockWaitTimeout'))
    expect(campaign.approved_digest).to eq(campaign.review_digest)
  end

  it 'does not clear a newer human approval when an older review request finishes later' do
    campaign.request_review!
    reviewed_digest = campaign.review_digest
    stub_request(:get, transport_path).to_return do
      JrcCampaigns::Campaign.find(campaign.id).update!(approved_by: admin, approved_at: Time.current,
                                                       approval_expires_at: 48.hours.from_now, approved_digest: reviewed_digest)
      { headers: { 'Content-Type' => 'application/json' }, body: transport.to_json }
    end
    expect { campaign.request_review! }.to raise_error(ActiveRecord::RecordInvalid)
    expect(campaign.reload.approved_digest).to eq(reviewed_digest)
    expect(campaign.approved_by_id).to eq(admin.id)
  end
end

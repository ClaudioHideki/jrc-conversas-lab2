require 'rails_helper'
require 'database_cleaner/active_record'
require 'timeout'

RSpec.describe 'Interrupted Broker campaign recovery' do # rubocop:disable RSpec/DescribeClass, RSpec/MultipleMemoizedHelpers
  self.use_transactional_tests = false
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:origin) { 'https://broker.example.test' }
  let(:integration_id) { SecureRandom.uuid }
  let(:instance_id) { SecureRandom.uuid }
  let(:prefix) { "#{origin}/v1/integrations/chatwoot/control" }
  let(:inbox) do
    create(:inbox, account: account, channel: create(:channel_api, account: account,
                                                                   webhook_url: "#{origin}/v1/integrations/chatwoot/#{integration_id}/events"))
  end
  let(:contact) { create(:contact, account: account, phone_number: '+5511999999000') }
  let(:campaign) do
    JrcCampaigns::Campaign.create!(account: account, inbox: inbox, created_by: admin, name: 'Synthetic interrupted dispatch',
                                   sending_window: { days: [0, 1, 2, 3, 4, 5, 6], start: '00:00', end: '23:59', timezone: 'UTC' })
  end
  let(:step) { campaign.steps.create!(kind: 'text', body: 'Synthetic message', position: 0) }
  let(:execution) { campaign.executions.create!(run_number: 1, status: 'running') }
  let(:recipient) do
    execution.recipients.create!(campaign: campaign, inbox: inbox, contact: contact, phone_number: contact.phone_number,
                                 destination: contact.phone_number)
  end
  let(:transport) do
    { protocol: 'chatwoot-campaigns/v1', integrationId: integration_id, instanceId: instance_id, inboxId: inbox.id,
      destinationRevision: 1, identityRevision: 2, ownerRevision: 0, numberSuffix: '0000', ready: true, reason: nil }
  end
  let(:intent_id) { '00000000-0000-4000-8000-000000000123' }
  let(:service) { JrcCampaigns::DispatchStepService.new(recipient: recipient, step: step) }
  let(:uploaded_keys) { [] }

  around do |example|
    disposable = Rails.env.test? && ActiveRecord::Base.connection.adapter_name == 'PostgreSQL' &&
                 ActiveRecord::Base.connection_db_config.database.end_with?('_test')
    raise 'Disposable PostgreSQL test database required' unless disposable

    DatabaseCleaner.clean_with(:deletion)
    with_modified_env('JRC_BROKER_ENABLED' => 'true', 'JRC_BROKER_ALLOWED_ORIGINS' => origin, 'FRONTEND_URL' => 'https://central.example.test',
                      'JRC_BROKER_CREDENTIAL_KEY' => Base64.strict_encode64('s' * 32)) { example.run }
  ensure
    clear_enqueued_jobs
    uploaded_keys.each { |key| ActiveStorage::Blob.service.delete(key) } if disposable
    DatabaseCleaner.clean_with(:deletion) if disposable
  end

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('broker.example.test').and_return(['93.184.216.34'])
    allow(ActiveStorage::Blob.service).to receive(:upload).and_wrap_original do |original, key, io, **options|
      uploaded_keys << key
      original.call(key, io, **options)
    end
    account.enable_features!('jrc_broker', 'jrc_campaigns')
    ciphertext = JrcBroker::Configuration.credential_store.encrypt(account_id: account.id, token: 'synthetic-scoped-key')
    integration = JrcBrokerIntegration.create!(account: account, broker_origin: origin, organization_id: SecureRandom.uuid,
                                               destination_revision: 1, encrypted_control_key: ciphertext)
    JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: integration_id, instance_id: instance_id)
    stub_request(:get, "#{prefix}/context").to_return(headers: { 'Content-Type' => 'application/json' }, body: {
      organizationId: integration.organization_id, accountId: account.id, destinationRevision: 1, chatwootOrigin: 'https://central.example.test'
    }.to_json)
    stub_request(:get, "#{prefix}/connections/#{integration_id}/campaign-transport")
      .to_return(headers: { 'Content-Type' => 'application/json' }, body: transport.to_json)
    stub_request(:get, "#{prefix}/connections/#{integration_id}/status")
      .to_return(headers: { 'Content-Type' => 'application/json' }, body: '{}')
    stub_request(:get, %r{#{Regexp.escape(prefix)}/connections/#{integration_id}/conversations/\d+/attendance}).to_return(status: 404)
    stub_request(:post, "#{prefix}/connections/#{integration_id}/campaign-intents")
      .to_return(status: 201, headers: { 'Content-Type' => 'application/json' }, body: {
        protocol: 'chatwoot-campaigns/v1', intentId: intent_id, state: 'RESERVED', expiresAt: 5.minutes.from_now.iso8601, replayed: false
      }.to_json)
    step
    campaign.request_review!
    campaign.approve!(admin, campaign.review_digest)
    campaign.update!(status: 'running')
    recipient
    clear_enqueued_jobs
  end

  it 'recovers an interrupted preflight automatically without resetting sending or creating another native message' do
    # Simulate process death outside StandardError rescue after the committed claim.
    stub_request(:get, "#{prefix}/connections/#{integration_id}/status").to_raise(Interrupt)
    expect { service.perform }.to raise_error(Interrupt)
    delivery = recipient.deliveries.sole
    expect(delivery).to be_sending
    expect(account.messages).to be_empty
    watchdog = enqueued_jobs.find { |job| job[:job].name == 'JrcCampaigns::BrokerRecoveryJob' }
    expect(watchdog).to be_present
    stub_request(:get, "#{prefix}/connections/#{integration_id}/status").to_return(body: '{}')

    travel 3.minutes do
      ActiveJob::Base.execute(watchdog)
    end

    expect(delivery.reload).to be_sending
    expect(delivery.metadata['message_id']).to eq(account.messages.sole.id)
    expect(account.messages.count).to eq(1)
  end

  it 'defers a 13:59 interrupted claim recovered at 14:02 until the next approved local sending window' do
    campaign.update!(status: 'draft', sending_window: { days: [1], start: '13:00', end: '14:00', timezone: 'America/Sao_Paulo' })
    campaign.request_review!
    campaign.approve!(admin, campaign.review_digest)
    campaign.update!(status: 'running')
    digest = campaign.approved_digest
    stub_request(:get, "#{prefix}/connections/#{integration_id}/status").to_raise(Interrupt)
    travel_to Time.utc(2026, 10, 26, 16, 59) do
      expect { service.perform }.to raise_error(Interrupt)
    end
    delivery = recipient.deliveries.sole
    stub_request(:get, "#{prefix}/connections/#{integration_id}/status").to_return(body: '{}')
    clear_enqueued_jobs

    travel_to Time.utc(2026, 10, 26, 17, 2) do
      JrcCampaigns::BrokerRecoveryJob.perform_now(delivery.id, delivery.metadata.fetch('dispatch_token'))
    end

    expect(account.messages).to be_empty
    expect(delivery.reload).to be_sending
    expect(campaign.reload.approved_digest).to eq(digest)
    watchdog = enqueued_jobs.find { |job| job[:job].name == 'JrcCampaigns::BrokerRecoveryJob' }
    expect(watchdog[:at]).to eq(Time.utc(2026, 11, 2, 16, 0).to_f)
    expect(a_request(:post, "#{prefix}/connections/#{integration_id}/campaign-intents")).not_to have_been_made
  end

  it 'does not create a native message when the original preflight crosses the approved window end' do
    campaign.update!(status: 'draft', sending_window: { days: [1], start: '13:00', end: '14:00', timezone: 'America/Sao_Paulo' })
    campaign.request_review!
    campaign.approve!(admin, campaign.review_digest)
    campaign.update!(status: 'running')
    stub_request(:get, "#{prefix}/connections/#{integration_id}/status").to_return do
      travel_to Time.utc(2026, 10, 26, 17, 2)
      { body: '{}' }
    end
    travel_to Time.utc(2026, 10, 26, 16, 59)

    service.perform

    expect(account.messages).to be_empty
    expect(recipient.deliveries.sole).to be_sending
    expect(enqueued_jobs.any? do |job|
      job[:job].name == 'JrcCampaigns::BrokerRecoveryJob' && job[:at].to_i == Time.utc(2026, 11, 2, 16, 0).to_i
    end).to be(true)
  ensure
    travel_back
  end

  it 'defers the original canonical callback outside the approved window before reserving any intent' do
    campaign.update!(status: 'draft', sending_window: { days: [1], start: '13:00', end: '14:00', timezone: 'America/Sao_Paulo' })
    campaign.request_review!
    campaign.approve!(admin, campaign.review_digest)
    campaign.update!(status: 'running')
    travel_to Time.utc(2026, 10, 26, 16, 59) do
      service.perform
    end
    delivery = recipient.deliveries.sole
    message = account.messages.sole
    clear_enqueued_jobs
    request = stub_request(:post, inbox.channel.webhook_url).to_return(status: 204)

    travel_to Time.utc(2026, 10, 26, 17, 2) do
      WebhookJob.perform_now(inbox.channel.webhook_url, message.webhook_data.merge(event: 'message_created'), :api_inbox_webhook,
                             secret: inbox.channel.secret, delivery_id: delivery.metadata.fetch('webhook_delivery_id'))
    end

    expect(a_request(:post, "#{prefix}/connections/#{integration_id}/campaign-intents")).not_to have_been_made
    expect(request).not_to have_been_requested
    expect(account.messages.count).to eq(1)
    expect(delivery.reload).to be_sending
    watchdog = enqueued_jobs.find { |job| job[:job].name == 'JrcCampaigns::BrokerRecoveryJob' }
    expect(watchdog[:at]).to eq(Time.utc(2026, 11, 2, 16, 0).to_f)
  end

  it 'defers the original callback when its intent reservation crosses the approved window end' do
    campaign.update!(status: 'draft', sending_window: { days: [1], start: '13:00', end: '14:00', timezone: 'America/Sao_Paulo' })
    campaign.request_review!
    campaign.approve!(admin, campaign.review_digest)
    campaign.update!(status: 'running')
    travel_to Time.utc(2026, 10, 26, 16, 59)
    service.perform
    delivery = recipient.deliveries.sole
    message = account.messages.sole
    stub_request(:post, "#{prefix}/connections/#{integration_id}/campaign-intents").to_return do
      travel_to Time.utc(2026, 10, 26, 17, 2)
      { status: 201, body: { protocol: 'chatwoot-campaigns/v1', intentId: intent_id, state: 'RESERVED', replayed: false }.to_json }
    end
    request = stub_request(:post, inbox.channel.webhook_url).to_return(status: 204)

    WebhookJob.perform_now(inbox.channel.webhook_url, message.webhook_data.merge(event: 'message_created'), :api_inbox_webhook,
                           secret: inbox.channel.secret, delivery_id: delivery.metadata.fetch('webhook_delivery_id'))

    expect(request).not_to have_been_requested
    expect(JrcBroker::WebhookDiagnostic.new(message.reload).read).to be_empty
    expect(message.additional_attributes['jrc_campaign_intent_id']).to eq(intent_id)
    expect(account.messages.count).to eq(1)
    expect(delivery.reload).to be_sending
  ensure
    travel_back
  end

  it 'commits one callback UUID with the canonical message and uses it in the original API callback' do
    service.perform
    delivery = recipient.deliveries.sole
    message = account.messages.sole
    uuid = message.additional_attributes['jrc_campaign_webhook_delivery_id']
    expect(uuid).to match(JrcBroker::Client::UUID)
    expect(delivery.metadata['webhook_delivery_id']).to eq(uuid)
    WebhookListener.instance.message_created(Events::Base.new('message.created', Time.current, message: message))
    callback = enqueued_jobs.find { |job| job[:job] == WebhookJob && job[:args][1]['event'] == 'message_created' }
    expect(callback[:args].last['delivery_id']).to eq(uuid)
  end

  it 'keeps the committed message recoverable when its after-commit event cannot enqueue' do
    allow(EventDispatcherJob).to receive(:perform_later).and_wrap_original do |original, name, *arguments|
      raise ActiveJob::EnqueueError, 'Synthetic enqueue interruption' if name == 'message.created'

      original.call(name, *arguments)
    end

    service.perform

    delivery = recipient.deliveries.sole
    expect(account.messages.count).to eq(1)
    expect(delivery).to be_sending
    expect(delivery.metadata['message_id']).to eq(account.messages.sole.id)
    expect(enqueued_jobs.any? { |job| job[:job].name == 'JrcCampaigns::BrokerRecoveryJob' }).to be(true)
  end

  it 'recovers the original native image attachment and caption without uploading a second message' do
    asset = account.jrc_campaign_media_assets.new(kind: 'image', created_by: admin)
    bytes = Rails.root.join('spec/assets/avatar.png').binread
    asset.file.attach(io: StringIO.new(bytes), filename: 'synthetic.png', content_type: 'image/png')
    asset.save!
    campaign.update!(status: 'draft')
    step.update!(kind: 'image', body: 'Synthetic caption', media_asset: asset, media_url: 'https://central.example.test/synthetic.png')
    campaign.request_review!
    campaign.approve!(admin, campaign.review_digest)
    campaign.update!(status: 'running')
    service.perform
    delivery = recipient.deliveries.sole
    message = account.messages.sole
    blob_id = message.attachments.sole.file.blob_id
    clear_enqueued_jobs

    travel 3.minutes do
      JrcCampaigns::BrokerRecoveryJob.perform_now(delivery.id, delivery.metadata.fetch('dispatch_token'))
    end

    expect(account.messages.count).to eq(1)
    expect(message.reload.content).to eq('Synthetic caption')
    expect(message.attachments.sole.file.blob_id).to eq(blob_id)
    expect(message.attachments.sole.file.download).to eq(bytes)
    expect(delivery.reload.metadata.fetch('message_id')).to eq(message.id)
  end

  it 'replays the same native message through WebhookJob after intent reservation was interrupted before local persistence' do
    service.perform
    delivery = recipient.deliveries.sole
    message = account.messages.sole
    key = "campaign:#{delivery.id}"
    reservation_keys = []
    stub_request(:post, "#{prefix}/connections/#{integration_id}/campaign-intents").to_return do |request|
      reservation_keys << request.headers['Idempotency-Key']
      raise Interrupt if reservation_keys.size == 1

      { status: 201, body: { protocol: 'chatwoot-campaigns/v1', intentId: intent_id, state: 'RESERVED', replayed: true }.to_json }
    end
    WebhookListener.instance.message_created(Events::Base.new('message.created', Time.current, message: message))
    callback = enqueued_jobs.find { |job| job[:job] == WebhookJob && job[:args][1]['event'] == 'message_created' }
    expect { ActiveJob::Base.execute(callback) }.to raise_error(Interrupt)
    expect(message.reload.additional_attributes['jrc_campaign_intent_id']).to be_nil
    delivered = []
    stub_request(:post, inbox.channel.webhook_url).to_return do |request|
      delivered << [JSON.parse(request.body).fetch('id'), request.headers.fetch('X-Chatwoot-Delivery')]
      { status: 204 }
    end
    clear_enqueued_jobs

    travel 3.minutes do
      JrcCampaigns::BrokerRecoveryJob.perform_now(delivery.id, delivery.metadata.fetch('dispatch_token'))
      perform_enqueued_jobs(only: WebhookJob)
    end

    expect(account.messages.count).to eq(1)
    expect(message.reload.additional_attributes['jrc_campaign_intent_id']).to eq(intent_id)
    expect(reservation_keys).to eq([key, key])
    expect(delivered).to eq([[message.id, delivery.reload.metadata.fetch('webhook_delivery_id')]])
  end

  %w[unknown in_flight accepted uncertain].each do |outcome|
    it "does not replay a canonical message with #{outcome} evidence" do
      service.perform
      delivery = recipient.deliveries.sole
      message = account.messages.sole
      if outcome == 'unknown'
        delivery.update!(status: 'unknown')
      else
        proof = { 'version' => 1, 'phase' => 'callback', 'outcome' => 'pending', outcome => true }
        message.update!(content_attributes: { 'jrc_broker_delivery' => proof })
      end
      clear_enqueued_jobs

      travel 3.minutes do
        JrcCampaigns::BrokerRecoveryJob.perform_now(delivery.id, delivery.metadata.fetch('dispatch_token'))
      end

      expect(enqueued_jobs.none? { |job| job[:job] == WebhookJob }).to be(true)
      expect(account.messages.count).to eq(1)
      expect(delivery.reload.status).to eq(outcome == 'unknown' ? 'unknown' : 'sending')
    end
  end

  %w[paused canceled].each do |state|
    it "preserves a #{state} campaign without recovering its interrupted claim" do
      delivery = recipient.deliveries.create!(inbox: inbox, step: step, status: 'sending', metadata: { 'dispatch_token' => 'old' })
      campaign.update!(status: state)
      JrcCampaigns::BrokerRecoveryJob.perform_now(delivery.id, 'old')
      expect(delivery.reload).to be_sending
      expect(account.messages).to be_empty
      expect(campaign.reload.status).to eq(state)
    end
  end

  it 'recovers the same canonical callback through normal resume after a paused watchdog consumed its wake-up' do
    service.perform
    delivery = recipient.deliveries.sole
    message = account.messages.sole
    uuid = message.additional_attributes.fetch('jrc_campaign_webhook_delivery_id')
    clear_enqueued_jobs
    campaign.pause!
    JrcCampaigns::BrokerRecoveryJob.perform_now(delivery.id, delivery.metadata.fetch('dispatch_token'))
    expect(recipient.reload.metadata['pending_step_id']).to eq(step.id)
    campaign.resume!
    dispatch = enqueued_jobs.find { |job| job[:job] == JrcCampaigns::DispatchStepJob }
    ActiveJob::Base.execute(dispatch)
    recovery = enqueued_jobs.find { |job| job[:job] == JrcCampaigns::BrokerRecoveryJob }
    expect(recovery).to be_present
    ActiveJob::Base.execute(recovery)
    callback = enqueued_jobs.find { |job| job[:job] == WebhookJob }
    expect(callback).to be_present
    sent = []
    stub_request(:post, inbox.channel.webhook_url).to_return do |request|
      sent << [JSON.parse(request.body).fetch('id'), request.headers.fetch('X-Chatwoot-Delivery')]
      { status: 204 }
    end

    ActiveJob::Base.execute(callback)

    expect(sent).to eq([[message.id, uuid]])
    expect(account.messages.count).to eq(1)
    expect(delivery.reload.metadata['webhook_delivery_id']).to eq(uuid)
  end

  it 'recovers a pre-message claim through normal resume after the paused watchdog consumed its wake-up' do
    stub_request(:get, "#{prefix}/connections/#{integration_id}/status").to_raise(Interrupt)
    expect { service.perform }.to raise_error(Interrupt)
    delivery = recipient.deliveries.sole
    clear_enqueued_jobs
    campaign.pause!
    JrcCampaigns::BrokerRecoveryJob.perform_now(delivery.id, delivery.metadata.fetch('dispatch_token'))
    expect(recipient.reload.metadata['pending_step_id']).to eq(step.id)
    campaign.resume!
    dispatch = enqueued_jobs.find { |job| job[:job] == JrcCampaigns::DispatchStepJob }
    ActiveJob::Base.execute(dispatch)
    recovery = enqueued_jobs.find { |job| job[:job] == JrcCampaigns::BrokerRecoveryJob }
    expect(recovery).to be_present
    stub_request(:get, "#{prefix}/connections/#{integration_id}/status").to_return(body: '{}')

    ActiveJob::Base.execute(recovery)

    expect(delivery.reload).to be_sending
    expect(delivery.metadata['message_id']).to eq(account.messages.sole.id)
    expect(recipient.deliveries.count).to eq(1)
  end

  it 'fences the original preflight worker after recovery takes the claim' do
    configuration = JrcCampaigns::BrokerConnector.for(inbox).public_configuration
    delivery = recipient.deliveries.create!(inbox: inbox, step: step, status: 'sending',
                                            metadata: { 'dispatch_token' => 'new', 'broker_connector' => configuration })
    JrcCampaigns::DispatchStepService.new(recipient: recipient, step: step, dispatch_token: 'old').perform
    expect(delivery.reload).to be_sending
    expect(account.messages).to be_empty
  end

  it 'does not let a resumed preflight overwrite the recovered lease or its canonical message' do
    recovered = false
    old_token = nil
    stub_request(:get, "#{prefix}/connections/#{integration_id}/status").to_return do
      unless recovered
        recovered = true
        delivery = recipient.deliveries.sole
        old_token = delivery.metadata.fetch('dispatch_token')
        travel 3.minutes do
          JrcCampaigns::BrokerRecoveryJob.perform_now(delivery.id, old_token)
        end
      end
      { body: '{}' }
    end

    service.perform

    delivery = recipient.deliveries.sole
    expect(delivery).to be_sending
    expect(delivery.metadata.fetch('dispatch_token')).not_to eq(old_token)
    expect(delivery.metadata.fetch('message_id')).to eq(account.messages.sole.id)
    expect(account.messages.count).to eq(1)
  end

  it 'drops a queued recovery callback if its delivery becomes unknown before WebhookJob executes' do
    service.perform
    delivery = recipient.deliveries.sole
    clear_enqueued_jobs
    travel 3.minutes do
      JrcCampaigns::BrokerRecoveryJob.perform_now(delivery.id, delivery.metadata.fetch('dispatch_token'))
    end
    callback = enqueued_jobs.find { |job| job[:job] == WebhookJob }
    expect(callback).to be_present
    delivery.reload.update!(status: 'unknown')
    request = stub_request(:post, inbox.channel.webhook_url).to_return(status: 204)

    ActiveJob::Base.execute(callback)

    expect(request).not_to have_been_requested
    expect(delivery.reload).to be_unknown
    expect(account.messages.count).to eq(1)
  end

  it 'drops a queued recovery callback if the original callback starts before WebhookJob executes' do
    service.perform
    delivery = recipient.deliveries.sole
    message = account.messages.sole
    clear_enqueued_jobs
    travel 3.minutes do
      JrcCampaigns::BrokerRecoveryJob.perform_now(delivery.id, delivery.metadata.fetch('dispatch_token'))
    end
    callback = enqueued_jobs.find { |job| job[:job] == WebhookJob }
    expect(callback).to be_present
    JrcBroker::WebhookDiagnostic.new(message).callback_started!
    request = stub_request(:post, inbox.channel.webhook_url).to_return(status: 204)

    ActiveJob::Base.execute(callback)

    expect(request).not_to have_been_requested
    expect(JrcBroker::WebhookDiagnostic.new(message.reload).read['in_flight']).to be(true)
  end

  it 'drops a queued recovery callback when its signed source configuration changes' do
    service.perform
    delivery = recipient.deliveries.sole
    clear_enqueued_jobs
    travel 3.minutes do
      JrcCampaigns::BrokerRecoveryJob.perform_now(delivery.id, delivery.metadata.fetch('dispatch_token'))
    end
    callback = enqueued_jobs.find { |job| job[:job] == WebhookJob }
    expect(callback).to be_present
    JrcBrokerInboxBinding.find_by!(inbox: inbox).update!(instance_id: SecureRandom.uuid)
    request = stub_request(:post, inbox.channel.webhook_url).to_return(status: 204)

    ActiveJob::Base.execute(callback)

    expect(request).not_to have_been_requested
    expect(delivery.reload).to be_sending
    expect(account.messages.count).to eq(1)
  end

  %w[in_flight accepted unknown].each do |outcome|
    it "preserves #{outcome} recorded during the intent HTTP without starting another callback" do
      service.perform
      delivery = recipient.deliveries.sole
      message = account.messages.sole
      clear_enqueued_jobs
      JrcCampaigns::BrokerRecoveryJob.perform_now(delivery.id, delivery.metadata.fetch('dispatch_token'))
      callback = enqueued_jobs.find { |job| job[:job] == WebhookJob }
      expect(callback).to be_present
      prior = nil
      stub_request(:post, "#{prefix}/connections/#{integration_id}/campaign-intents").to_return do
        diagnostic = JrcBroker::WebhookDiagnostic.new(message.reload)
        if outcome == 'unknown'
          delivery.reload.update!(status: 'unknown')
        else
          diagnostic.callback_started!
          diagnostic.callback_accepted! if outcome == 'accepted'
        end
        prior = diagnostic.read
        { status: 201, body: { protocol: 'chatwoot-campaigns/v1', intentId: intent_id, state: 'RESERVED', replayed: false }.to_json }
      end
      request = stub_request(:post, inbox.channel.webhook_url).to_return(status: 204)

      ActiveJob::Base.execute(callback)

      expect(request).not_to have_been_requested
      expect(JrcBroker::WebhookDiagnostic.new(message.reload).read).to eq(prior)
      expect(delivery.reload).to be_unknown if outcome == 'unknown'
      expect(account.messages.count).to eq(1)
    end
  end

  it 'settles a no-reply follow-up interrupted before message creation when the recipient replies' do
    campaign.update!(status: 'draft')
    step.update!(only_if_no_reply: true)
    campaign.request_review!
    campaign.approve!(admin, campaign.review_digest)
    campaign.update!(status: 'running')
    stub_request(:get, "#{prefix}/connections/#{integration_id}/status").to_raise(Interrupt)
    expect { service.perform }.to raise_error(Interrupt)
    delivery = recipient.deliveries.sole
    recipient.update!(status: 'replied', replied_at: Time.current)
    stub_request(:get, "#{prefix}/connections/#{integration_id}/status").to_return(body: '{}')

    JrcCampaigns::BrokerRecoveryJob.perform_now(delivery.id, delivery.metadata.fetch('dispatch_token'))

    expect(delivery.reload).to be_skipped
    expect(account.messages).to be_empty
    expect(recipient.reload).to be_replied
    expect(campaign.reload).not_to be_paused
  end

  it 'settles a proven pre-provider canonical no-reply follow-up after a reply and survives the late receipt tick' do
    campaign.update!(status: 'draft')
    step.update!(only_if_no_reply: true)
    campaign.request_review!
    campaign.approve!(admin, campaign.review_digest)
    campaign.update!(status: 'running')
    service.perform
    delivery = recipient.deliveries.sole
    recipient.update!(status: 'replied', replied_at: Time.current)
    clear_enqueued_jobs

    JrcCampaigns::BrokerRecoveryJob.perform_now(delivery.id, delivery.metadata.fetch('dispatch_token'))
    message = account.messages.sole
    receipt_url = "#{prefix}/connections/#{integration_id}/conversations/#{message.conversation.display_id}/campaign-messages/#{message.id}"
    stub_request(:get, receipt_url).to_return(status: 404)
    JrcCampaigns::BrokerStatusJob.perform_now('campaign', delivery.id, 19)

    expect(enqueued_jobs.none? { |job| job[:job] == WebhookJob }).to be(true)
    expect(account.messages.count).to eq(1)
    expect(delivery.reload).to be_skipped
    expect(recipient.reload).to be_replied
    expect(a_request(:get, receipt_url)).not_to have_been_made
  end

  %w[binding approval].each do |change|
    it "visibly pauses a proven pre-provider canonical message after #{change} drift instead of consuming all wakeups" do
      service.perform
      delivery = recipient.deliveries.sole
      message = account.messages.sole
      if change == 'binding'
        JrcBrokerInboxBinding.find_by!(inbox: inbox).update!(instance_id: SecureRandom.uuid)
      else
        campaign.update!(approval_expires_at: 1.minute.ago)
      end
      clear_enqueued_jobs
      receipt_url = "#{prefix}/connections/#{integration_id}/conversations/#{message.conversation.display_id}/campaign-messages/#{message.id}"
      stub_request(:get, receipt_url).to_return(status: 404)

      JrcCampaigns::BrokerRecoveryJob.perform_now(delivery.id, delivery.metadata.fetch('dispatch_token'))
      JrcCampaigns::BrokerStatusJob.perform_now('campaign', delivery.id, 19)

      expect(campaign.reload).to be_paused
      expect(delivery.reload).to be_sending
      expect(delivery.error_message).to be_present
      expect(recipient.reload.metadata['pending_step_id']).to eq(step.id)
      expect(a_request(:get, receipt_url)).not_to have_been_made
      expect(enqueued_jobs.none? { |job| job[:job] == WebhookJob }).to be(true)
    end
  end

  it 'rejects an identity revision changed after canonical creation instead of reserving with unapproved identity' do
    service.perform
    delivery = recipient.deliveries.sole
    message = account.messages.sole
    stub_request(:get, "#{prefix}/connections/#{integration_id}/campaign-transport")
      .to_return(body: transport.merge(identityRevision: 3).to_json)
    request = stub_request(:post, inbox.channel.webhook_url).to_return(status: 204)

    WebhookJob.perform_now(inbox.channel.webhook_url, message.webhook_data.merge(event: 'message_created'), :api_inbox_webhook,
                           secret: inbox.channel.secret, delivery_id: delivery.metadata.fetch('webhook_delivery_id'))

    expect(a_request(:post, "#{prefix}/connections/#{integration_id}/campaign-intents")).not_to have_been_made
    expect(request).not_to have_been_requested
    expect(account.messages.count).to eq(1)
  end

  it 'keeps an existing intent immutable and blocks its callback after the approved identity changes' do
    service.perform
    delivery = recipient.deliveries.sole
    message = account.messages.sole
    JrcCampaigns::BrokerIntentReservation.new(message).prepare!(message.webhook_data)
    stub_request(:get, "#{prefix}/connections/#{integration_id}/campaign-transport")
      .to_return(body: transport.merge(identityRevision: 3).to_json)
    request = stub_request(:post, inbox.channel.webhook_url).to_return(status: 204)

    WebhookJob.perform_now(inbox.channel.webhook_url, message.webhook_data.merge(event: 'message_created'), :api_inbox_webhook,
                           secret: inbox.channel.secret, delivery_id: delivery.metadata.fetch('webhook_delivery_id'))

    expect(request).not_to have_been_requested
    expect(a_request(:post, "#{prefix}/connections/#{integration_id}/campaign-intents")).to have_been_made.once
    expect(message.reload.additional_attributes['jrc_campaign_intent_id']).to eq(intent_id)
    expect(account.messages.count).to eq(1)
  end

  context 'when a previous step fails during the current preflight' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:previous_step) { campaign.steps.create!(position: 0, kind: 'text', body: 'Synthetic previous step') }
    let(:previous_delivery) do
      recipient.deliveries.create!(step: previous_step, inbox: inbox, external_id: "synthetic:previous:#{recipient.id}",
                                   status: 'sent', sent_at: Time.current)
    end

    before do
      campaign.update!(status: 'draft')
      step.update!(position: 1)
      previous_step
      campaign.request_review!
      campaign.approve!(admin, campaign.review_digest)
      campaign.update!(status: 'running')
      previous_delivery
    end

    it 'preserves the real late recipient failure before creating another native message' do
      stub_request(:get, "#{prefix}/connections/#{integration_id}/status").to_return do
        JrcCampaigns::StatusTrackerService.call(external_id: previous_delivery.external_id, status: 'failed')
        { body: '{}' }
      end

      service.perform

      expect(recipient.reload).to be_failed
      expect(campaign.reload).to be_running
      expect(account.messages).to be_empty
    end

    it 'preserves a real late recipient failure during intent HTTP without posting the canonical callback' do
      service.perform
      delivery = recipient.deliveries.find_by!(step: step)
      message = account.messages.sole
      stub_request(:post, "#{prefix}/connections/#{integration_id}/campaign-intents").to_return do
        JrcCampaigns::StatusTrackerService.call(external_id: previous_delivery.external_id, status: 'failed')
        { status: 201, body: { protocol: 'chatwoot-campaigns/v1', intentId: intent_id, state: 'RESERVED', replayed: false }.to_json }
      end
      request = stub_request(:post, inbox.channel.webhook_url).to_return(status: 204)

      WebhookJob.perform_now(inbox.channel.webhook_url, message.webhook_data.merge(event: 'message_created'), :api_inbox_webhook,
                             secret: inbox.channel.secret, delivery_id: delivery.metadata.fetch('webhook_delivery_id'))

      expect(request).not_to have_been_requested
      expect(recipient.reload).to be_failed
      expect(account.messages.count).to eq(1)
    end
  end

  context 'when the real listener callback is safely deferred before the provider' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:delivery) { recipient.deliveries.find_by!(step: step) }
    let(:message) { account.messages.sole }
    let(:receipt_url) do
      "#{prefix}/connections/#{integration_id}/conversations/#{message.conversation.display_id}/campaign-messages/#{message.id}"
    end

    before do
      campaign.update!(status: 'draft', sending_window: { days: [1, 2], start: '13:00', end: '14:00', timezone: 'America/Sao_Paulo' })
      campaign.request_review!
      campaign.approve!(admin, campaign.review_digest)
      campaign.update!(status: 'running')
      travel_to Time.utc(2026, 10, 26, 16, 59)
      service.perform
      WebhookListener.instance.message_created(Events::Base.new('message.created', Time.current, message: message))
      callback = enqueued_jobs.find { |job| job[:job] == WebhookJob }
      travel_to Time.utc(2026, 10, 26, 17, 2)
      ActiveJob::Base.execute(callback)
      stub_request(:get, receipt_url).to_return(status: 404)
    end

    it 'survives all twenty receipt ticks and sends the same UUID once at the next window' do
      20.times { |attempt| JrcCampaigns::BrokerStatusJob.perform_now('campaign', delivery.id, attempt) }
      expect(delivery.reload).to be_sending
      expect(campaign.reload).to be_running
      expect(a_request(:get, receipt_url)).not_to have_been_made
      watchdog = enqueued_jobs.find do |job|
        job[:job] == JrcCampaigns::BrokerRecoveryJob && job[:at].to_i == Time.utc(2026, 10, 27, 16, 0).to_i
      end
      clear_enqueued_jobs
      sent = []
      stub_request(:post, inbox.channel.webhook_url).to_return do |request|
        sent << [JSON.parse(request.body).fetch('id'), request.headers.fetch('X-Chatwoot-Delivery')]
        { status: 204 }
      end
      travel_to Time.utc(2026, 10, 27, 16, 0)
      ActiveJob::Base.execute(watchdog)
      callback = enqueued_jobs.find { |job| job[:job] == WebhookJob && job[:args].last['campaign_recovery_token'] }
      ActiveJob::Base.execute(callback)

      expect(sent).to eq([[message.id, delivery.reload.metadata.fetch('webhook_delivery_id')]])
      expect(enqueued_jobs.any? { |job| job[:job] == JrcCampaigns::BrokerStatusJob }).to be(true)
      expect(account.messages.count).to eq(1)
    end

    it 'keeps a safe paused deferral out of UNKNOWN even after approval and the old receipt deadline expire' do
      campaign.pause!
      JrcCampaigns::BrokerRecoveryJob.perform_now(delivery.id, delivery.metadata.fetch('dispatch_token'))
      travel_to Time.utc(2026, 10, 29, 17, 2)

      20.times { |attempt| JrcCampaigns::BrokerStatusJob.perform_now('campaign', delivery.id, attempt) }

      expect(delivery.reload).to be_sending
      expect(campaign.reload).to be_paused
      expect(recipient.reload.metadata['pending_step_id']).to eq(step.id)
      expect(a_request(:get, receipt_url)).not_to have_been_made
    end

    %w[in_flight accepted uncertain].each do |proof|
      it "does not suppress or restart existing receipt polling once callback proof becomes #{proof}" do
        diagnostic = JrcBroker::WebhookDiagnostic.new(message)
        diagnostic.callback_started!
        diagnostic.callback_accepted! if proof == 'accepted'
        diagnostic.failure!(Timeout::Error.new, phase: 'callback') if proof == 'uncertain'

        JrcCampaigns::BrokerStatusJob.perform_now('campaign', delivery.id, 19)

        expect(a_request(:get, receipt_url)).to have_been_made.once
        expect(delivery.reload).to be_unknown
        expect(campaign.reload).to be_paused
      end
    end

    it 'never treats an already UNKNOWN delivery as a safe deferred send' do
      delivery.update!(status: 'unknown')

      JrcCampaigns::BrokerStatusJob.perform_now('campaign', delivery.id, 19)

      expect(a_request(:get, receipt_url)).to have_been_made.once
      expect(delivery.reload).to be_unknown
    end

    %w[false exception].each do |failure|
      it "keeps proven-safe deferral retryable if the fresh receipt enqueue returns #{failure}" do
        watchdog = enqueued_jobs.find do |job|
          job[:job] == JrcCampaigns::BrokerRecoveryJob && job[:at].to_i == Time.utc(2026, 10, 27, 16, 0).to_i
        end
        clear_enqueued_jobs
        travel_to Time.utc(2026, 10, 27, 16, 0)
        ActiveJob::Base.execute(watchdog)
        callback = enqueued_jobs.find { |job| job[:job] == WebhookJob && job[:args].last['campaign_recovery_token'] }
        configured = JrcCampaigns::BrokerStatusJob.set(wait: 10.seconds)
        if failure == 'exception'
          allow(configured).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, 'Synthetic queue unavailable')
        else
          allow(configured).to receive(:perform_later).and_return(false)
        end
        allow(JrcCampaigns::BrokerStatusJob).to receive(:set).with(wait: 10.seconds).and_return(configured)
        request = stub_request(:post, inbox.channel.webhook_url).to_return(status: 204)

        ActiveJob::Base.execute(callback)
        JrcCampaigns::BrokerStatusJob.perform_now('campaign', delivery.id, 19)

        expect(request).not_to have_been_requested
        expect(JrcBroker::WebhookDiagnostic.new(message.reload).read).to be_empty
        expect(delivery.reload).to be_sending
        expect(enqueued_jobs.any? { |job| job[:job] == JrcCampaigns::BrokerRecoveryJob }).to be(true)
      end
    end
  end

  %w[blacklist approval identity].each do |change|
    it "does not send an interrupted preflight after #{change} changes" do
      delivery = recipient.deliveries.create!(inbox: inbox, step: step, status: 'sending', metadata: { 'dispatch_token' => 'old' })
      case change
      when 'blacklist' then account.jrc_campaign_blacklists.create!(phone_number: contact.phone_number, reason: 'Synthetic blacklist')
      when 'approval' then campaign.update!(approval_expires_at: 1.minute.ago)
      when 'identity'
        stub_request(:get, "#{prefix}/connections/#{integration_id}/campaign-transport").to_return(body: transport.merge(identityRevision: 3).to_json)
      end
      JrcCampaigns::BrokerRecoveryJob.perform_now(delivery.id, 'old')
      expect(account.messages).to be_empty
      expect(delivery.reload).not_to be_sent
    end
  end

  it 'bounds abandoned callback recovery without replacing the canonical message' do
    service.perform
    delivery = recipient.deliveries.sole
    8.times do
      travel 3.minutes do
        JrcCampaigns::BrokerRecoveryJob.perform_now(delivery.id, delivery.reload.metadata.fetch('dispatch_token'))
      end
    end
    expect(enqueued_jobs.count { |job| job[:job] == WebhookJob && job[:args].last['campaign_recovery_token'].present? }).to eq(5)
    expect(account.messages.count).to eq(1)
    expect(delivery.reload).to be_sending
  end

  it 'keeps a canonical message queued locally from exhausting receipts before its callback dequeues' do
    service.perform
    delivery = recipient.deliveries.sole
    message = account.messages.sole
    receipt_url = "#{prefix}/connections/#{integration_id}/conversations/#{message.conversation.display_id}/campaign-messages/#{message.id}"
    stub_request(:get, receipt_url).to_return(status: 404)

    20.times { |attempt| JrcCampaigns::BrokerStatusJob.perform_now('campaign', delivery.id, attempt) }

    expect(delivery.reload).to be_sending
    expect(campaign.reload).to be_running
    expect(a_request(:get, receipt_url)).not_to have_been_made
    expect(account.messages.count).to eq(1)
  end

  it 'keeps a legacy unmarked canonical message conservative instead of manufacturing safe deferral proof' do
    service.perform
    delivery = recipient.deliveries.sole
    message = account.messages.sole
    delivery.update!(metadata: delivery.metadata.except('broker_callback_deferred'))
    receipt_url = "#{prefix}/connections/#{integration_id}/conversations/#{message.conversation.display_id}/campaign-messages/#{message.id}"
    stub_request(:get, receipt_url).to_return(status: 404)

    JrcCampaigns::BrokerStatusJob.perform_now('campaign', delivery.id, 19)

    expect(delivery.reload).to be_unknown
    expect(a_request(:get, receipt_url)).to have_been_made.once
  end

  it 'resumes an exhausted safe canonical message through the UI with the same UUID and a fresh bounded lease' do
    service.perform
    delivery = recipient.deliveries.sole
    message = account.messages.sole
    uuid = delivery.metadata.fetch('webhook_delivery_id')
    6.times { JrcCampaigns::BrokerRecoveryJob.perform_now(delivery.id, delivery.reload.metadata.fetch('dispatch_token')) }
    expect(campaign.reload).to be_paused
    expect(recipient.reload.metadata['pending_step_id']).to eq(step.id)
    old_token = delivery.reload.metadata.fetch('dispatch_token')
    clear_enqueued_jobs

    campaign.resume!

    expect(delivery.reload.metadata['dispatch_token']).not_to eq(old_token)
    expect(delivery.metadata['recovery_attempts']).to eq(0)
    dispatch = enqueued_jobs.find { |job| job[:job] == JrcCampaigns::DispatchStepJob }
    expect(dispatch).to be_present
    ActiveJob::Base.execute(dispatch)
    recovery = enqueued_jobs.find { |job| job[:job] == JrcCampaigns::BrokerRecoveryJob && !job[:at] }
    ActiveJob::Base.execute(recovery)
    callback = enqueued_jobs.find { |job| job[:job] == WebhookJob && job[:args].last['campaign_recovery_token'] }
    sent = []
    stub_request(:post, inbox.channel.webhook_url).to_return do |request|
      sent << [JSON.parse(request.body).fetch('id'), request.headers.fetch('X-Chatwoot-Delivery')]
      { status: 204 }
    end
    ActiveJob::Base.execute(callback)

    expect(sent).to eq([[message.id, uuid]])
    expect(account.messages.count).to eq(1)
  end

  it 'resumes an exhausted pre-message claim without server intervention or a second delivery' do
    stub_request(:get, "#{prefix}/connections/#{integration_id}/status").to_raise(Interrupt)
    expect { service.perform }.to raise_error(Interrupt)
    delivery = recipient.deliveries.sole
    5.times do
      expect do
        JrcCampaigns::BrokerRecoveryJob.perform_now(delivery.id, delivery.reload.metadata.fetch('dispatch_token'))
      end.to raise_error(Interrupt)
    end
    JrcCampaigns::BrokerRecoveryJob.perform_now(delivery.id, delivery.reload.metadata.fetch('dispatch_token'))
    expect(campaign.reload).to be_paused
    expect(recipient.reload.metadata['pending_step_id']).to eq(step.id)
    clear_enqueued_jobs
    stub_request(:get, "#{prefix}/connections/#{integration_id}/status").to_return(body: '{}')

    campaign.resume!
    dispatch = enqueued_jobs.find { |job| job[:job] == JrcCampaigns::DispatchStepJob }
    ActiveJob::Base.execute(dispatch)
    recovery = enqueued_jobs.find { |job| job[:job] == JrcCampaigns::BrokerRecoveryJob && !job[:at] }
    ActiveJob::Base.execute(recovery)

    expect(recipient.deliveries.count).to eq(1)
    expect(account.messages.count).to eq(1)
    expect(delivery.reload.metadata['recovery_attempts']).to eq(1)
  end

  %w[in_flight accepted uncertain].each do |proof|
    it "does not reset an exhausted recovery fence or budget after callback evidence becomes #{proof}" do
      service.perform
      delivery = recipient.deliveries.sole
      message = account.messages.sole
      6.times { JrcCampaigns::BrokerRecoveryJob.perform_now(delivery.id, delivery.reload.metadata.fetch('dispatch_token')) }
      old_token = delivery.reload.metadata.fetch('dispatch_token')
      diagnostic = JrcBroker::WebhookDiagnostic.new(message)
      diagnostic.callback_started!
      diagnostic.callback_accepted! if proof == 'accepted'
      diagnostic.failure!(Timeout::Error.new, phase: 'callback') if proof == 'uncertain'
      clear_enqueued_jobs

      campaign.reload.resume!

      expect(delivery.reload.metadata['recovery_attempts']).to eq(5)
      expect(delivery.metadata['dispatch_token']).to eq(old_token)
      expect(enqueued_jobs.none? { |job| job[:job] == WebhookJob }).to be(true)
    end
  end

  it 'allows only one native message when two recovery workers overlap on committed PostgreSQL rows' do
    delivery = recipient.deliveries.create!(inbox: inbox, step: step, status: 'sending', metadata: { 'dispatch_token' => 'old' })
    id = delivery.id
    ActiveRecord::Base.connection_pool.release_connection
    workers = Array.new(2) do
      Thread.new do
        JrcCampaigns::BrokerRecoveryJob.perform_now(id, 'old')
      ensure
        ActiveRecord::Base.connection_pool.release_connection
      end
    end
    Timeout.timeout(15) { workers.each(&:value) }
    expect(account.messages.count).to eq(1)
    expect(delivery.reload.metadata['message_id']).to eq(account.messages.sole.id)
  ensure
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end

  # The complete callback path must share the same sole pool slot and committed rows.
  it 'releases the only pool slot at every preflight and intent HTTP boundary for a reentrant PostgreSQL callback' do # rubocop:disable RSpec/ExampleLength
    link = create(:contact_inbox, contact: contact, inbox: inbox, source_id: 'jrc-00000000-0000-4000-8000-000000000456')
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: link)
    original_configuration = ActiveRecord::Base.connection_db_config.configuration_hash
    ActiveRecord::Base.establish_connection(original_configuration.merge(pool: 1, checkout_timeout: 0.5))
    states = []
    paths = {
      "#{prefix}/context" => { organizationId: JrcBrokerIntegration.find_by!(account: account).organization_id, accountId: account.id,
                               destinationRevision: 1, chatwootOrigin: 'https://central.example.test' },
      "#{prefix}/connections/#{integration_id}/status" => {},
      "#{prefix}/connections/#{integration_id}/campaign-transport" => transport,
      "#{prefix}/connections/#{integration_id}/conversations/#{conversation.display_id}/attendance" => {
        organizationId: JrcBrokerIntegration.find_by!(account: account).organization_id, integrationId: integration_id,
        accountId: account.id, inboxId: inbox.id, remoteContactId: contact.id, remoteConversationId: conversation.display_id,
        channelId: SecureRandom.uuid, conversationId: SecureRandom.uuid, destinationRevision: 1, credentialRevision: 1,
        ownerRevision: 0, attendanceRevision: 1, controlRevision: 1, mode: 'HUMAN'
      }
    }
    paths.each do |path, body|
      stub_request(:get, path).to_return do
        states << ActiveRecord::Base.connection_pool.active_connection?.present?
        worker = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection { JrcCampaigns::Recipient.find(recipient.id) }
          :available
        end
        expect(Timeout.timeout(3) { worker.value }).to eq(:available)
        { body: body.to_json }
      ensure
        worker&.kill if worker&.alive?
        worker&.join
      end
    end
    service.perform
    message = account.messages.sole
    stub_request(:post, "#{prefix}/connections/#{integration_id}/campaign-intents").to_return do
      states << ActiveRecord::Base.connection_pool.active_connection?.present?
      { status: 201, body: { protocol: 'chatwoot-campaigns/v1', intentId: intent_id, state: 'RESERVED', replayed: false }.to_json }
    end
    JrcCampaigns::BrokerIntentReservation.new(message).prepare!(message.webhook_data)
    callback_states = []
    stub_request(:post, inbox.channel.webhook_url).to_return do
      callback_states << ActiveRecord::Base.connection_pool.active_connection?.present?
      worker = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Message.transaction { Message.lock('FOR UPDATE NOWAIT').find(message.id) }
        end
        :available
      end
      expect(Timeout.timeout(3) { worker.value }).to eq(:available)
      { status: 204 }
    ensure
      worker&.kill if worker&.alive?
      worker&.join
    end
    WebhookJob.perform_now(inbox.channel.webhook_url, message.webhook_data.merge(event: 'message_created'), :api_inbox_webhook,
                           secret: inbox.channel.secret, delivery_id: message.additional_attributes.fetch('jrc_campaign_webhook_delivery_id'))
    expect(states).not_to be_empty
    expect(states).to all(be(false))
    expect(callback_states).to eq([false])
  ensure
    ActiveRecord::Base.establish_connection(original_configuration) if original_configuration
  end
end

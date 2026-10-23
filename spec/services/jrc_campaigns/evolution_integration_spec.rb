require 'rails_helper'

RSpec.describe 'Evolution campaign integration', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account, webhook_url: 'https://evolution.example.test/chatwoot/webhook/demo')) }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999999000') }
  let(:configuration) do
    { account_id: account.id, inbox_id: inbox.id, base_url: 'https://evolution.example.test', instance: 'demo',
      sender_number: '551155550000', api_key_env: 'JRC_CAMPAIGNS_EVOLUTION_DEMO_API_KEY', min_interval_seconds: 60, daily_limit: 2 }
  end
  let(:campaign) do
    JrcCampaigns::Campaign.create!(account: account, inbox: inbox, created_by: admin, name: 'Demo QA', delay_min_seconds: 60, delay_max_seconds: 60,
                                   sending_window: { days: [0, 1, 2, 3, 4, 5, 6], start: '00:00', end: '23:59' })
  end
  let(:step) { campaign.steps.create!(kind: 'text', body: 'Olá {{nome}}', position: 0) }
  let(:execution) { campaign.executions.create!(run_number: 1, status: 'running') }
  let(:recipient) do
    execution.recipients.create!(campaign: campaign, inbox: inbox, contact: contact, phone_number: contact.phone_number,
                                 destination: contact.phone_number)
  end
  let(:service) { JrcCampaigns::DispatchStepService.new(recipient: recipient, step: step) }
  let(:connector) { JrcCampaigns::EvolutionConnector.for(inbox) }
  let(:send_url) { 'https://evolution.example.test/message/sendText/demo' }
  let(:test_idempotency_key) { SecureRandom.uuid }
  let(:test_options) do
    { account: account, user: admin, phone_number: contact.phone_number, inbox_id: inbox.id,
      step: { kind: 'text', body: 'Homologação' }, idempotency_key: test_idempotency_key, operator_confirmed: true }
  end

  around do |example|
    travel_to(Time.current.change(hour: 12, min: 0, sec: 0))
    with_modified_env('JRC_CAMPAIGNS_EVOLUTION_CONNECTORS' => [configuration].to_json,
                      'JRC_CAMPAIGNS_EVOLUTION_DEMO_API_KEY' => 'isolated-qa-key') { example.run }
  ensure
    travel_back
  end

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('evolution.example.test').and_return(['93.184.216.34'])
    stub_request(:get, 'https://evolution.example.test/instance/fetchInstances?instanceName=demo').to_return(
      headers: { 'Content-Type' => 'application/json' },
      body: [{ name: 'demo', ownerJid: '551155550000@s.whatsapp.net', connectionStatus: 'open' }].to_json
    )
    stub_request(:post, send_url).with(headers: { 'Apikey' => 'isolated-qa-key' }).to_return do |request|
      number = JSON.parse(request.body).fetch('number')
      { status: 201, headers: { 'Content-Type' => 'application/json' },
        body: { key: { id: 'qa-provider-id', fromMe: true, remoteJid: "#{number}@s.whatsapp.net" }, status: 'PENDING' }.to_json }
    end
    JrcCampaigns::Consent.create!(account: account, recorded_by: admin, phone_number: contact.phone_number,
                                 evidence: 'QA only: campaign and individual test authorization', granted_at: Time.current, purpose: 'whatsapp_campaigns')
  end

  context 'with an approved campaign' do
    before do
      step
      campaign.request_review!
      campaign.approve!(admin, campaign.review_digest)
      campaign.update!(status: 'running')
    end

    it 'sends once, records the external ID and avoids webhook or reply-job duplicates' do
      service.perform
      service.perform
      expect(a_request(:post, send_url)).to have_been_made.once
      delivery = recipient.deliveries.sole
      expect(delivery).to have_attributes(status: 'sent', external_id: "evolution:#{account.id}:#{inbox.id}:qa-provider-id", delivered_at: nil)
      message = Message.find(delivery.metadata.fetch('message_id'))
      expect(message.source_id).to eq('WAID:qa-provider-id')
      listener = WebhookListener.instance
      expect(WebhookJob).not_to receive(:perform_later)
      listener.send(:deliver_api_inbox_webhooks, message.webhook_data.merge(event: 'message_created'), inbox)
      expect(Messages::SendEmailNotificationService).not_to receive(:new)
      SendReplyJob.new.deliver(message)
    end

    it 'does not resend an ambiguous timeout and halts the campaign and connector' do
      stub_request(:post, send_url).to_timeout
      2.times { service.perform }
      expect(a_request(:post, send_url)).to have_been_made.once
      expect(recipient.deliveries.sole.status).to eq('unknown')
      expect(campaign.reload).to be_paused
      expect(inbox.channel.reload.additional_attributes.dig('jrc_campaign_evolution_state', 'halted_reason')).to be_present
    end

    it 'treats an HTTP 200 without an external message ID as unknown' do
      stub_request(:post, send_url).to_return(headers: { 'Content-Type' => 'application/json' }, body: { message: 'bot' }.to_json)
      service.perform
      expect(recipient.deliveries.sole.status).to eq('unknown')
      expect(recipient.reload.sent_at).to be_nil
    end

    it 'treats an explicit provider rejection as failed and stops later sends' do
      stub_request(:post, send_url).to_return(status: 429)
      service.perform
      expect(recipient.deliveries.sole).to be_failed
      expect(campaign.reload).to be_paused
    end

    it 'rechecks revoked consent before dispatch' do
      JrcCampaigns::Consent.find_by!(account: account, phone_number: contact.phone_number).update!(revoked_at: Time.current)
      service.perform
      expect(recipient.reload).to be_skipped
      expect(a_request(:post, send_url)).not_to have_been_made
    end

    it 'rechecks consent after sender preflight' do
      allow_any_instance_of(JrcCampaigns::EvolutionClient).to receive(:verify_sender!) do
        JrcCampaigns::Consent.find_by!(account: account, phone_number: contact.phone_number).update!(revoked_at: Time.current)
      end
      service.perform
      expect(a_request(:post, send_url)).not_to have_been_made
    end

    it 'preserves cancellation during sender preflight' do
      allow_any_instance_of(JrcCampaigns::EvolutionClient).to receive(:verify_sender!) { campaign.cancel! }
      service.perform
      expect(campaign.reload).to be_canceled
      expect(a_request(:post, send_url)).not_to have_been_made
    end

    it 'keeps paused preflight work queued for a safe resume' do
      allow_any_instance_of(JrcCampaigns::EvolutionClient).to receive(:verify_sender!) { campaign.pause! }
      service.perform
      expect(campaign.reload).to be_paused
      expect(recipient.deliveries.sole).to be_queued
      expect(recipient.reload.metadata['pending_step_id']).to eq(step.id)
      expect(a_request(:post, send_url)).not_to have_been_made
    end

    it 'defers overdue or resumed work outside the sending window' do
      campaign.update!(status: 'draft', sending_window: { days: [0, 1, 2, 3, 4, 5, 6], start: '00:00', end: '00:01' })
      campaign.request_review!
      campaign.approve!(admin, campaign.review_digest)
      campaign.update!(status: 'running')
      service.perform
      expect(recipient.deliveries.sole).to be_queued
      expect(a_request(:post, send_url)).not_to have_been_made
    end

    it 'does not claim or resend a delivery after a worker restart' do
      recipient.deliveries.create!(step: step, inbox: inbox, status: 'sending')
      service.perform
      expect(a_request(:post, send_url)).not_to have_been_made
    end

    it 'updates delivery only from a real provider acknowledgment' do
      service.perform
      delivery = recipient.deliveries.sole
      stub_request(:post, 'https://evolution.example.test/chat/findMessages/demo').to_return(
        headers: { 'Content-Type' => 'application/json' }, body: {
          messages: { records: [{ key: { id: 'qa-provider-id', fromMe: true }, MessageUpdate: [{ status: 'DELIVERY_ACK' }] }] }
        }.to_json
      )
      JrcCampaigns::EvolutionStatusJob.new.perform('campaign', delivery.id)
      expect(delivery.reload).to be_delivered
      expect(recipient.reload).to be_delivered
      expect(Message.find(delivery.metadata['message_id'])).to be_delivered
    end

    it 'does not let status polling for another message confirm this delivery' do
      service.perform
      delivery = recipient.deliveries.sole
      stub_request(:post, 'https://evolution.example.test/chat/findMessages/demo').to_return(
        headers: { 'Content-Type' => 'application/json' }, body: {
          messages: { records: [{ key: { id: 'other-id', fromMe: true }, MessageUpdate: [{ status: 'READ' }] }] }
        }.to_json
      )
      JrcCampaigns::EvolutionStatusJob.new.perform('campaign', delivery.id)
      expect(delivery.reload).to be_sent
      expect(delivery.delivered_at).to be_nil
    end
  end

  it 'requires explicit confirmation for an individual test' do
    expect { JrcCampaigns::TestMessageService.new(**test_options.merge(operator_confirmed: false)).perform }.to raise_error(ArgumentError, /Confirme/)
    expect(a_request(:post, send_url)).not_to have_been_made
  end

  it 'makes repeated test requests idempotent without claiming delivery' do
    first = JrcCampaigns::TestMessageService.new(**test_options).perform
    second = JrcCampaigns::TestMessageService.new(**test_options).perform
    expect(first[:message_id]).to eq('qa-provider-id')
    expect(second[:test_delivery_id]).to eq(first[:test_delivery_id])
    expect(first[:delivery_confirmed]).to be(false)
    expect(a_request(:post, send_url)).to have_been_made.once
  end

  it 'retains an unknown test and does not repeat it' do
    stub_request(:post, send_url).to_timeout
    expect(JrcCampaigns::TestMessageService.new(**test_options).perform[:status]).to eq('unknown')
    repeated = JrcCampaigns::TestMessageService.new(**test_options).perform
    expect(repeated[:status]).to eq('unknown')
    expect(a_request(:post, send_url)).to have_been_made.once
  end

  it 'allows new deliberate tests with the same continuous consent after the interval' do
    consent = JrcCampaigns::Consent.find_by!(account: account, phone_number: contact.phone_number)
    original = consent.attributes
    first = JrcCampaigns::TestMessageService.new(**test_options).perform
    travel 61.seconds do
      second = JrcCampaigns::TestMessageService.new(**test_options.merge(idempotency_key: SecureRandom.uuid)).perform
      expect(second[:status]).to eq('sent')
      expect(second[:test_delivery_id]).not_to eq(first[:test_delivery_id])
    end
    expect(consent.reload.attributes).to eq(original)
    expect(JrcCampaigns::TestAuthorization.where(account: account)).to be_empty
    expect(a_request(:post, send_url)).to have_been_made.twice
  end

  it 'prefers continuous consent without consuming an optional single-test authorization' do
    authorization = JrcCampaigns::TestAuthorization.create!(
      account: account, inbox: inbox, recorded_by: admin, phone_number: contact.phone_number, evidence: 'Only one optional test',
      granted_at: Time.current, connector_snapshot: connector.public_configuration.slice(*JrcCampaigns::TestAuthorization::IDENTITY_FIELDS)
    )
    expect(JrcCampaigns::TestMessageService.new(**test_options).perform[:status]).to eq('sent')
    expect(authorization.reload.consumed_at).to be_nil
  end

  it 'uses the explicitly requested destination without inventing consent for it' do
    expect do
      expect(JrcCampaigns::TestMessageService.new(**test_options.merge(phone_number: '+5511999999001')).perform[:status]).to eq('sent')
    end.not_to change(JrcCampaigns::Consent, :count)
    expect(a_request(:post, send_url)).to have_been_made.once
  end
  it 'stops later continuous tests after revocation' do
    JrcCampaigns::TestMessageService.new(**test_options).perform
    JrcCampaigns::Consent.find_by!(account: account, phone_number: contact.phone_number).update!(revoked_at: Time.current)
    travel 61.seconds do
      expect do
        JrcCampaigns::TestMessageService.new(**test_options.merge(idempotency_key: SecureRandom.uuid)).perform
      end.to raise_error(ArgumentError, /revogado/)
    end
    expect(a_request(:post, send_url)).to have_been_made.once
  end

  it 'does not allow a revoked test destination' do
    JrcCampaigns::Consent.find_by!(account: account, phone_number: contact.phone_number).update!(revoked_at: Time.current)
    expect { JrcCampaigns::TestMessageService.new(**test_options).perform }.to raise_error(ArgumentError, /revogado/)
  end

  context 'with authorization for only one test' do
    let(:authorization) do
      JrcCampaigns::TestAuthorization.create!(
        account: account, inbox: inbox, recorded_by: admin, phone_number: contact.phone_number,
        evidence: 'Synthetic holder authorizes one individual test, no campaigns.', granted_at: Time.current,
        connector_snapshot: connector.public_configuration.slice(*JrcCampaigns::TestAuthorization::IDENTITY_FIELDS)
      )
    end

    before do
      JrcCampaigns::Consent.find_by!(account: account, phone_number: contact.phone_number).update!(purpose: nil)
      authorization
    end

    it 'preserves optional single-test history and the operational interval without requiring another grant' do
      consent = JrcCampaigns::Consent.find_by!(account: account, phone_number: contact.phone_number)
      historical_attributes = consent.attributes
      first = JrcCampaigns::TestMessageService.new(**test_options).perform
      expect(first[:status]).to eq('sent')
      expect(authorization.reload).to have_attributes(test_delivery_id: first[:test_delivery_id], consumed_at: Time.current)
      expect(consent.reload.attributes).to eq(historical_attributes)
      expect(JrcCampaigns::AudienceResolver.new(campaign).entries.map(&:phone_number)).to include(contact.phone_number)
      expect(JrcCampaigns::TestMessageService.new(**test_options).perform[:test_delivery_id]).to eq(first[:test_delivery_id])
      expect(JrcCampaigns::TestMessageService.new(**test_options.merge(idempotency_key: SecureRandom.uuid)).perform[:status]).to eq('failed')
      expect(a_request(:post, send_url)).to have_been_made.once
    end

    it 'consumes an unknown attempt and never automatically sends again' do
      stub_request(:post, send_url).to_timeout
      expect(JrcCampaigns::TestMessageService.new(**test_options).perform[:status]).to eq('unknown')
      expect(authorization.reload.consumed_at).to be_present
      expect(JrcCampaigns::TestMessageService.new(**test_options).perform[:status]).to eq('unknown')
      expect { JrcCampaigns::TestMessageService.new(**test_options.merge(idempotency_key: SecureRandom.uuid)).perform }
        .to raise_error(ArgumentError, /pendente/)
      expect(a_request(:post, send_url)).to have_been_made.once
    end

    it 'consumes a provider rejection without permitting another request' do
      stub_request(:post, send_url).to_return(status: 429)
      expect(JrcCampaigns::TestMessageService.new(**test_options).perform[:status]).to eq('failed')
      expect(authorization.reload.consumed_at).to be_present
      expect(JrcCampaigns::TestMessageService.new(**test_options.merge(idempotency_key: SecureRandom.uuid)).perform[:status]).to eq('failed')
      expect(a_request(:post, send_url)).to have_been_made.once
    end

    it 'does not use revoked authorization' do
      authorization.update!(revoked_at: Time.current)
      expect { JrcCampaigns::TestMessageService.new(**test_options).perform }.to raise_error(ArgumentError)
      expect(authorization.reload.consumed_at).to be_nil
      expect(a_request(:post, send_url)).not_to have_been_made
    end

    it 'rechecks revocation after sender preflight' do
      allow_any_instance_of(JrcCampaigns::EvolutionClient).to receive(:verify_sender!) { authorization.update!(revoked_at: Time.current) }
      expect(JrcCampaigns::TestMessageService.new(**test_options).perform[:status]).to eq('failed')
      expect(authorization.reload.consumed_at).to be_present
      expect(a_request(:post, send_url)).not_to have_been_made
    end

    it 'keeps blacklist protection for a separately authorized test' do
      account.jrc_campaign_blacklists.create!(phone_number: contact.phone_number, reason: 'QA blacklist')
      expect { JrcCampaigns::TestMessageService.new(**test_options).perform }.to raise_error(ArgumentError, /blacklist/)
      expect(authorization.reload.consumed_at).to be_nil
      expect(a_request(:post, send_url)).not_to have_been_made
    end

    it 'keeps blocked contact protection for a separately authorized test' do
      contact.update!(blocked: true)
      expect { JrcCampaigns::TestMessageService.new(**test_options).perform }.to raise_error(ArgumentError, /bloqueado/)
      expect(authorization.reload.consumed_at).to be_nil
    end

    it 'uses a new explicitly requested destination without consuming another destinations authorization' do
      expect(JrcCampaigns::TestMessageService.new(**test_options.merge(phone_number: '+5511999999001')).perform[:status]).to eq('sent')
      expect(authorization.reload.consumed_at).to be_nil
      expect(a_request(:post, send_url)).to have_been_made.once
    end
    it 'does not reuse authorization for a changed sender' do
      with_modified_env('JRC_CAMPAIGNS_EVOLUTION_CONNECTORS' => [configuration.merge(sender_number: '551155550001')].to_json) do
        expect { JrcCampaigns::TestMessageService.new(**test_options).perform }.to raise_error(ArgumentError, /remetente/)
      end
      expect(authorization.reload.consumed_at).to be_nil
      expect(a_request(:post, send_url)).not_to have_been_made
    end

    it 'keeps a worker claim consumed after a restart without calling the provider' do
      payload_digest = Digest::SHA256.hexdigest([inbox.id, contact.phone_number, { 'kind' => 'text', 'body' => 'Homologação', 'media_url' => nil, 'file_name' => nil }.to_json].to_json)
      claimed = JrcCampaigns::TestDelivery.create!(account: account, inbox: inbox, requested_by: admin,
                                                  idempotency_key: test_idempotency_key, phone_number: contact.phone_number, payload_digest: payload_digest)
      authorization.update!(consumed_at: Time.current, test_delivery: claimed)
      expect(JrcCampaigns::TestMessageService.new(**test_options).perform[:status]).to eq('unknown')
      expect(a_request(:post, send_url)).not_to have_been_made
      expect do
        JrcCampaigns::TestMessageService.new(**test_options.merge(idempotency_key: SecureRandom.uuid)).perform
      end.to raise_error(ArgumentError)
    end

    it 'returns existing history after authorization revocation without resending' do
      first = JrcCampaigns::TestMessageService.new(**test_options).perform
      authorization.update!(revoked_at: Time.current)
      expect(JrcCampaigns::TestMessageService.new(**test_options).perform[:test_delivery_id]).to eq(first[:test_delivery_id])
      expect(a_request(:post, send_url)).to have_been_made.once
    end
  end

  it 'does not invent campaign purpose for historical consent evidence' do
    JrcCampaigns::Consent.find_by!(account: account, phone_number: contact.phone_number).update!(purpose: nil)
    consent = JrcCampaigns::Consent.find_by!(account: account, phone_number: contact.phone_number)
    original = consent.attributes
    expect(JrcCampaigns::TestMessageService.new(**test_options).perform[:status]).to eq('sent')
    expect(consent.reload.attributes).to eq(original)
    expect(JrcCampaigns::AudienceResolver.new(campaign).entries.map(&:phone_number)).to include(contact.phone_number)
  end

  it 'rejects a blocked or malformed destination' do
    contact.update!(blocked: true)
    expect { JrcCampaigns::TestMessageService.new(**test_options).perform }.to raise_error(ArgumentError, /bloqueado/)
    expect(JrcCampaigns::EligibilityPolicy.new(account: account, phone_number: '+0000').rejection_reason).to eq('Telefone inválido.')
  end

  it 'shares the interval and daily limits between campaigns and tests' do
    gate = JrcCampaigns::EvolutionSafetyGate.new(connector)
    gate.reserve!
    gate.complete!
    expect { gate.reserve! }.to raise_error(JrcCampaigns::EvolutionSafetyGate::Throttled)
    travel 61.seconds do
      gate.reserve!
      gate.complete!
    end
    travel 122.seconds do
      expect { gate.reserve! }.to raise_error(JrcCampaigns::EvolutionSafetyGate::Halted, /diário/)
    end
  end

  it 'blocks later attempts if a worker crashed before persisting an external result' do
    gate = JrcCampaigns::EvolutionSafetyGate.new(connector)
    gate.reserve!
    travel 61.seconds do
      expect { gate.reserve! }.to raise_error(JrcCampaigns::EvolutionSafetyGate::Halted, /resultado persistido/)
    end
  end

  it 'rejects reusing a test key for a different message' do
    JrcCampaigns::TestMessageService.new(**test_options).perform
    expect do
      JrcCampaigns::TestMessageService.new(**test_options.merge(step: { kind: 'text', body: 'Changed' })).perform
    end.to raise_error(ArgumentError, /outra solicitação/)
    expect(a_request(:post, send_url)).to have_been_made.once
  end

  it 'scopes test history to the current account and denies regular agents' do
    account.enable_features!('jrc_campaigns')
    result = JrcCampaigns::TestMessageService.new(**test_options).perform
    path = "/api/v1/accounts/#{account.id}/jrc_campaigns/test_deliveries/#{result[:test_delivery_id]}"
    get path, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['delivery_confirmed']).to be(false)
    foreign_account = create(:account)
    foreign_account.enable_features!('jrc_campaigns')
    foreign_admin = create(:user, account: foreign_account, role: :administrator)
    get "/api/v1/accounts/#{foreign_account.id}/jrc_campaigns/test_deliveries/#{result[:test_delivery_id]}", headers: foreign_admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    get path, headers: create(:user, account: account, role: :agent).create_new_auth_token
    expect(response).to have_http_status(:forbidden)
  end

  %w[image document video audio].each do |kind|
    it "uses the existing instance for #{kind} without a second webhook send" do
      endpoint = kind == 'audio' ? 'sendWhatsAppAudio' : 'sendMedia'
      allow(Resolv).to receive(:getaddresses).with('media.example.test').and_return(['93.184.216.34'])
      stub_request(:get, 'https://media.example.test/file').to_return(
        headers: { 'Content-Type' => kind == 'document' ? 'application/pdf' : "#{kind}/test" }, body: 'isolated-media-fixture'
      )
      stub_request(:post, "https://evolution.example.test/message/#{endpoint}/demo").to_return(
        status: 201, headers: { 'Content-Type' => 'application/json' },
        body: { key: { id: "qa-#{kind}", fromMe: true, remoteJid: '5511999999000@s.whatsapp.net' } }.to_json
      )
      result = JrcCampaigns::TestMessageService.new(**test_options.merge(step: { kind: kind, media_url: 'https://media.example.test/file', body: '' })).perform
      expect(result[:message_id]).to eq("qa-#{kind}")
      expect(result[:delivery_confirmed]).to be(false)
      expect(a_request(:post, "https://evolution.example.test/message/#{endpoint}/demo").with do |request|
        payload = JSON.parse(request.body)
        encoded = payload[kind == 'audio' ? 'audio' : 'media'] == Base64.strict_encode64('isolated-media-fixture')
        encoded && (kind == 'audio' || (payload['fileName'].present? && payload['mimetype'].present?))
      end).to have_been_made.once
      expect(Message.find(JrcCampaigns::TestDelivery.find(result[:test_delivery_id]).metadata['message_id']).attachments.count).to eq(1)
    end
  end

  it 'does not expose the Evolution internal network through a media URL' do
    allow(Resolv).to receive(:getaddresses).with('internal.example.test').and_return(['127.0.0.1'])
    result = JrcCampaigns::TestMessageService.new(**test_options.merge(step: { kind: 'image', media_url: 'https://internal.example.test/secret' })).perform
    expect(result[:status]).to eq('failed')
    expect(a_request(:post, 'https://evolution.example.test/message/sendMedia/demo')).not_to have_been_made
  end

  it 'does not request a provider send after a media download times out' do
    allow(Resolv).to receive(:getaddresses).with('media.example.test').and_return(['93.184.216.34'])
    stub_request(:get, 'https://media.example.test/file').to_timeout
    result = JrcCampaigns::TestMessageService.new(**test_options.merge(step: { kind: 'image', media_url: 'https://media.example.test/file' })).perform
    expect(result[:status]).to eq('failed')
    expect(a_request(:post, 'https://evolution.example.test/message/sendMedia/demo')).not_to have_been_made
  end

  it 'rejects media whose response type differs from the selected kind' do
    allow(Resolv).to receive(:getaddresses).with('media.example.test').and_return(['93.184.216.34'])
    stub_request(:get, 'https://media.example.test/file').to_return(headers: { 'Content-Type' => 'text/html' }, body: '<html>not an image</html>')
    result = JrcCampaigns::TestMessageService.new(**test_options.merge(step: { kind: 'image', media_url: 'https://media.example.test/file' })).perform
    expect(result[:status]).to eq('failed')
    expect(a_request(:post, 'https://evolution.example.test/message/sendMedia/demo')).not_to have_been_made
  end

  it 'rejects media above the conservative size limit before requesting the provider' do
    allow(Resolv).to receive(:getaddresses).with('media.example.test').and_return(['93.184.216.34'])
    stub_request(:get, 'https://media.example.test/file').to_return(headers: { 'Content-Type' => 'image/png' }, body: 'x' * (10.megabytes + 1))
    result = JrcCampaigns::TestMessageService.new(**test_options.merge(step: { kind: 'image', media_url: 'https://media.example.test/file' })).perform
    expect(result[:status]).to eq('failed')
    expect(a_request(:post, 'https://evolution.example.test/message/sendMedia/demo')).not_to have_been_made
  end

  it 'exposes only the explicitly configured API inbox, without its credential' do
    account.enable_features!('jrc_campaigns')
    unconfigured = create(:inbox, account: account, channel: create(:channel_api, account: account))
    get "/api/v1/accounts/#{account.id}/jrc_campaigns/metadata", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    boxes = response.parsed_body['whatsapp_inboxes']
    expect(boxes.map { |item| item['id'] }).to include(inbox.id)
    expect(boxes.map { |item| item['id'] }).not_to include(unconfigured.id)
    expect(boxes.find { |item| item['id'] == inbox.id }['phone_number']).to eq('551155550000')
    expect(response.body).not_to include('isolated-qa-key', 'api_key_env')
  end

  it 'rejects an inbox from another account even if the ID is supplied directly' do
    expect do
      JrcCampaigns::TestMessageService.new(**test_options.merge(account: create(:account)))
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'does not authorize generic API inboxes or a mismatched webhook' do
    other = create(:inbox, account: account, channel: create(:channel_api, account: account))
    expect(campaign.accepts_sending_inbox?(other)).to be_falsey
    inbox.channel.update!(webhook_url: 'https://other.example.test/chatwoot/webhook/demo')
    expect { JrcCampaigns::EvolutionConnector.for(inbox) }.to raise_error(ArgumentError, /webhook/)
  end

  it 'requires a new review when connector identity changes' do
    step
    campaign.request_review!
    campaign.approve!(admin, campaign.review_digest)
    with_modified_env('JRC_CAMPAIGNS_EVOLUTION_CONNECTORS' => [configuration.merge(sender_number: '551155550001')].to_json) do
      expect(campaign.approval_valid?).to be_falsey
    end
  end

  it 'rejects a sender mismatch before attempting the external send' do
    stub_request(:get, 'https://evolution.example.test/instance/fetchInstances?instanceName=demo').to_return(
      headers: { 'Content-Type' => 'application/json' },
      body: [{ name: 'demo', ownerJid: '551155550001@s.whatsapp.net', connectionStatus: 'open' }].to_json
    )
    expect(JrcCampaigns::TestMessageService.new(**test_options).perform[:status]).to eq('failed')
    expect(a_request(:post, send_url)).not_to have_been_made
  end

  it 'rejects Meta templates and short campaign intervals on the API inbox' do
    campaign.steps.create!(kind: 'template', position: 0, template_name: 'official', template_language: 'pt_BR')
    expect { campaign.request_review! }.to raise_error(ActiveRecord::RecordInvalid, /Templates/)
    campaign.steps.destroy_all
    step
    campaign.update!(delay_min_seconds: 5)
    expect { campaign.request_review! }.to raise_error(ActiveRecord::RecordInvalid, /intervalo/)
  end
end

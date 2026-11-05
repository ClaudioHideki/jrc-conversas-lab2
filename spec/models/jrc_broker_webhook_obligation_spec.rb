require 'rails_helper'

RSpec.describe 'Durable Broker message obligation', type: :model do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let!(:binding) do
    JrcBrokerIntegration.create!(account: account, broker_origin: 'https://broker.example.test', organization_id: SecureRandom.uuid,
                                 destination_revision: 1, encrypted_control_key: 'synthetic-not-used')
    JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid)
  end
  let(:message) { build(:message, account: account, inbox: inbox, message_type: :outgoing) }

  it 'captures one durable native CSAT obligation and suppresses the duplicate listener delivery' do
    inbox.update!(csat_survey_enabled: true, csat_config: { 'message' => 'Synthetic CSAT' })
    conversation = create(:conversation, account: account, inbox: inbox, status: :resolved)
    with_modified_env(FRONTEND_URL: 'https://hml.example.test') do
      2.times { CsatSurveyService.new(conversation: conversation).perform }
    end
    survey = conversation.messages.find_by!(content_type: :input_csat)
    obligation = JrcBrokerWebhookObligation.find_by(message_id: survey.id)
    expect(obligation).to be_present
    expect(JrcBrokerWebhookObligation.where(message_id: survey.id).count).to eq(1)
    expect(obligation.payload).to include(
      'event' => 'message_created', 'id' => survey.id, 'message_type' => 'template', 'content_type' => 'input_csat',
      'private' => false, 'sender' => nil,
      'content' => "Synthetic CSAT https://hml.example.test/survey/responses/#{conversation.uuid}"
    )
    expect(obligation.payload.dig('account', 'id')).to eq(account.id)
    expect(obligation.payload.dig('inbox', 'id')).to eq(inbox.id)
    expect(obligation.payload.dig('conversation', 'id')).to eq(conversation.display_id)
    event = Events::Base.new('message.created', Time.current, message: survey)
    expect { WebhookListener.instance.message_created(event) }.not_to have_enqueued_job(WebhookJob)
  end

  it 'does not capture other templates, bot-authored CSAT templates or private CSAT notes' do
    bot = create(:agent_bot, account: account)
    conversation = create(:conversation, account: account, inbox: inbox)
    excluded = [
      Message.create!(account: account, inbox: inbox, conversation: conversation, message_type: :template, content_type: :text),
      Message.create!(account: account, inbox: inbox, conversation: conversation,
                      message_type: :template, content_type: :input_csat, sender: bot),
      Message.create!(account: account, inbox: inbox, conversation: conversation,
                      message_type: :template, content_type: :input_csat, private: true)
    ]

    expect(JrcBrokerWebhookObligation.where(message_id: excluded.map(&:id))).to be_empty
  end

  it 'retries native CSAT after a lost ACK with the same delivery identity' do
    survey = MessageTemplates::Template::CsatSurvey.new(conversation: message.conversation).perform
    obligation = JrcBrokerWebhookObligation.find_by(message_id: survey.id)
    expect(obligation).to be_present
    identities = []
    allow(SafeFetch).to receive(:fetch) do |_url, **options|
      identities << options.fetch(:headers).fetch('X-Chatwoot-Delivery')
      raise Errno::ECONNRESET if identities.one?
    end

    JrcBroker::WebhookObligationJob.perform_now(obligation.id)
    expect(obligation.reload.state).to eq('pending')
    travel 20.minutes do
      2.times { JrcBroker::WebhookObligationJob.perform_now(obligation.id) }
    end
    expect(obligation.reload.state).to eq('delivered')
    expect(identities).to eq([obligation.delivery_id, obligation.delivery_id])
    expect(survey.reload).to be_template
  end

  it 'keeps the message and its obligation when dispatch after COMMIT fails' do
    allow(message).to receive(:dispatch_create_events).and_raise('synthetic process boundary')
    expect { message.save! }.to raise_error('synthetic process boundary')
    expect(Message.exists?(message.id)).to be(true)
    expect(JrcBrokerWebhookObligation.find_by!(message_id: message.id).state).to eq('pending')
  end

  it 'rolls back the obligation with the message' do
    Message.transaction do
      message.save!
      raise ActiveRecord::Rollback
    end
    expect(JrcBrokerWebhookObligation.where(message_id: message.id)).to be_empty
  end

  it 'recovers Broker downtime with the same delivery identity and ignores duplicate jobs' do
    message.save!
    obligation = JrcBrokerWebhookObligation.find_by!(message_id: message.id)
    delivery_ids = []
    allow(SafeFetch).to receive(:fetch) do |_url, **options|
      delivery_ids << options.fetch(:headers).fetch('X-Chatwoot-Delivery')
      raise Errno::ECONNREFUSED if delivery_ids.one?
    end
    JrcBroker::WebhookObligationJob.perform_now(obligation.id)
    expect(obligation.reload.state).to eq('pending')
    travel 20.minutes do
      JrcBroker::WebhookObligationJob.perform_now(obligation.id)
      JrcBroker::WebhookObligationJob.perform_now(obligation.id)
    end
    expect(obligation.reload.state).to eq('delivered')
    expect(delivery_ids).to eq([obligation.delivery_id, obligation.delivery_id])
  end

  it 'rejects a replaced binding instead of sending the old message' do
    message.save!
    obligation = JrcBrokerWebhookObligation.find_by!(message_id: message.id)
    binding.update!(instance_id: SecureRandom.uuid)
    expect(SafeFetch).not_to receive(:fetch)
    JrcBroker::WebhookObligationJob.perform_now(obligation.id)
    expect(obligation.reload.state).to eq('rejected')
  end

  it 'recovers an enqueue failure from PostgreSQL without the listener sending twice' do
    allow(JrcBroker::WebhookObligationJob).to receive(:perform_later).and_raise(Errno::ECONNREFUSED)
    expect { message.save! }.not_to raise_error
    obligation = JrcBrokerWebhookObligation.find_by!(message_id: message.id)
    allow(JrcBroker::WebhookObligationJob).to receive(:perform_later).and_call_original
    expect { JrcBroker::WebhookRecoveryJob.perform_now }.to have_enqueued_job(JrcBroker::WebhookObligationJob).with(obligation.id)
    event = Events::Base.new('message.created', Time.current, message: message)
    expect { WebhookListener.instance.message_created(event) }.not_to have_enqueued_job(WebhookJob)
  end

  it 'recovers an expired process lease and preserves the delivery ID after a lost ACK' do
    message.save!
    obligation = JrcBrokerWebhookObligation.find_by!(message_id: message.id)
    obligation.update!(state: 'running', lease_token: SecureRandom.uuid, lease_until: 1.minute.ago)
    effects = Set.new
    calls = 0
    allow(SafeFetch).to receive(:fetch) do |_url, **options|
      effects << options.fetch(:headers).fetch('X-Chatwoot-Delivery')
      calls += 1
      raise Errno::ECONNRESET if calls == 1
    end
    JrcBroker::WebhookObligationJob.perform_now(obligation.id)
    travel 20.minutes do
      JrcBroker::WebhookObligationJob.perform_now(obligation.id)
      JrcBroker::WebhookObligationJob.perform_now(obligation.id)
    end
    expect(obligation.reload.state).to eq('delivered')
    expect(calls).to eq(2)
    expect(effects.to_a).to eq([obligation.delivery_id])
  end

  it 'does not capture private messages or direct Evolution campaigns' do
    message.private = true
    message.save!
    campaign = create(:message, account: account, inbox: inbox, message_type: :outgoing,
                                additional_attributes: { jrc_campaign_evolution: true })
    expect(JrcBrokerWebhookObligation.where(message_id: [message.id, campaign.id])).to be_empty
  end

  it 'marks the message failed after a terminal rejection' do
    message.save!
    obligation = JrcBrokerWebhookObligation.find_by!(message_id: message.id)
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('403 synthetic rejection'))
    JrcBroker::WebhookObligationJob.perform_now(obligation.id)
    expect(obligation.reload.state).to eq('failed')
    expect(message.reload.status).to eq('failed')
  end

  it 'does not send again after an exhausted lease expires' do
    message.save!
    obligation = JrcBrokerWebhookObligation.find_by!(message_id: message.id)
    obligation.update!(state: 'running', attempts: 8, lease_token: SecureRandom.uuid, lease_until: 1.minute.ago)
    expect(SafeFetch).not_to receive(:fetch)
    JrcBroker::WebhookObligationJob.perform_now(obligation.id)
    expect(obligation.reload.state).to eq('failed')
  end

  it 'allows deletion of an account without orphaning its delivery obligations' do
    message.save!
    expect { account.destroy! }.not_to raise_error
    expect(JrcBrokerWebhookObligation.where(account_id: account.id)).to be_empty
  end

  it 'rolls back terminal settlement if updating the message fails' do
    message.save!
    obligation = JrcBrokerWebhookObligation.find_by!(message_id: message.id)
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('403 synthetic rejection'))
    allow(Messages::StatusUpdateService).to receive(:new).and_raise(ActiveRecord::StatementInvalid, 'synthetic DB failure')
    expect { JrcBroker::WebhookObligationJob.perform_now(obligation.id) }.to raise_error(ActiveRecord::StatementInvalid)
    expect(obligation.reload.state).to eq('running')
    expect(message.reload.status).to eq('sent')
  end

  it 'preserves a delivered message when a late terminal attempt fails' do
    message.save!
    obligation = JrcBrokerWebhookObligation.find_by!(message_id: message.id)
    message.update!(status: :delivered)
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('403 synthetic rejection'))
    JrcBroker::WebhookObligationJob.perform_now(obligation.id)
    expect(obligation.reload.state).to eq('failed')
    expect(message.reload.status).to eq('delivered')
  end

  it 'keeps a campaign callback identity instead of allocating a second identity' do
    callback_id = SecureRandom.uuid
    message.additional_attributes = { 'jrc_campaign_broker' => true, 'jrc_campaign_webhook_delivery_id' => callback_id }
    message.save!
    expect(JrcBrokerWebhookObligation.find_by!(message_id: message.id).delivery_id).to eq(callback_id)
  end

  it 'does not acknowledge an obligation when campaign preparation defers the callback' do
    message.save!
    obligation = JrcBrokerWebhookObligation.find_by!(message_id: message.id)
    reservation = instance_double(JrcCampaigns::BrokerIntentReservation, prepare!: false)
    allow(JrcCampaigns::BrokerIntentReservation).to receive(:new).and_return(reservation)
    expect(SafeFetch).not_to receive(:fetch)
    JrcBroker::WebhookObligationJob.perform_now(obligation.id)
    expect(obligation.reload.state).to eq('pending')
    expect(obligation.attempts).to eq(0)
    expect(message.reload.status).to eq('sent')
  end

  it 'does not acknowledge an obligation when the callback ownership gate declines sending' do
    message.save!
    obligation = JrcBrokerWebhookObligation.find_by!(message_id: message.id)
    reservation = instance_double(JrcCampaigns::BrokerIntentReservation, prepare!: true, start_callback!: false)
    allow(JrcCampaigns::BrokerIntentReservation).to receive(:new).and_return(reservation)
    message.update_columns(additional_attributes: { 'jrc_campaign_broker' => true })
    expect(SafeFetch).not_to receive(:fetch)
    JrcBroker::WebhookObligationJob.perform_now(obligation.id)
    expect(obligation.reload.state).to eq('pending')
  end

  it 'captures the due time from the application clock at message commit' do
    travel_to Time.utc(2026, 10, 26, 16, 59) do
      message.save!
      expect(JrcBrokerWebhookObligation.find_by!(message_id: message.id).available_at).to eq(Time.current)
    end
  end

  it 'does not confirm protected attachment delivery when no HTTP callback was made' do
    message.save!
    obligation = JrcBrokerWebhookObligation.find_by!(message_id: message.id)
    allow(JrcServiceDesk::OutboundAttachments).to receive(:protected?).and_return(true)
    expect(SafeFetch).not_to receive(:fetch)
    JrcBroker::WebhookObligationJob.perform_now(obligation.id)
    expect(obligation.reload.state).not_to eq('delivered')
    expect(message.reload).to be_failed
  end

  it 'does not confirm a Service Desk wrapper that declined to invoke the callback' do
    message.content_attributes = { 'service_desk_delivery_id' => 0 }
    message.save!
    obligation = JrcBrokerWebhookObligation.find_by!(message_id: message.id)
    expect(SafeFetch).not_to receive(:fetch)
    JrcBroker::WebhookObligationJob.perform_now(obligation.id)
    expect(obligation.reload.state).not_to eq('delivered')
  end

  it 'keeps a real survey wrapper timeout uncertain and never retries its external effect' do
    message.save!
    assignment = JrcRelationship::Assignment.create!(account: account, contact: message.conversation.contact, status: 'active')
    survey = JrcRelationship::Survey.create!(
      account: account, assignment: assignment, kind: 'csat', token_digest: SecureRandom.hex(32),
      expires_at: 1.day.from_now, status: 'queued', metadata: { 'sent_message_id' => message.id }
    )
    # Eligibility is isolated; wrapper perform/rescue and its UNKNOWN persistence remain real.
    message.update!(content_attributes: { 'relationship_survey_id' => survey.id, 'relationship_survey_link' => 'https://example.test/synthetic' },
                    additional_attributes: { 'template_params' => { 'name' => 'synthetic_template' } })
    boundary = JrcRelationship::SurveyMessageExecution.new(message)
    allow(boundary).to receive(:claim).and_return(true)
    allow(boundary).to receive(:blocker).and_return(nil)
    allow(JrcRelationship::SurveyMessageExecution).to receive(:new).and_return(boundary)
    expect(SafeFetch).to receive(:fetch).once.and_raise(Errno::ECONNRESET)
    obligation = JrcBrokerWebhookObligation.find_by!(message_id: message.id)
    JrcBroker::WebhookObligationJob.perform_now(obligation.id)
    expect(survey.reload.status).to eq('unknown')
    expect(obligation.reload.state).to eq('failed')
    expect(obligation.last_error_code).to eq('JRC_BROKER_DELIVERY_OUTCOME_UNCERTAIN')
    travel 20.minutes do
      JrcBroker::WebhookObligationJob.perform_now(obligation.id)
    end
    expect(survey.reload.status).to eq('unknown')
  end
end

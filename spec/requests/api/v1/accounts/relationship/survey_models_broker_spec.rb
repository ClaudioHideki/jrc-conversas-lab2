# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Survey V3 Broker sender and guarded webhook transport' do
  include_context 'Service Desk survey models V3'
  let(:channel) { create(:channel_api, account: sd_account) }
  let(:inbox) { channel.inbox }
  let(:integration_id) { SecureRandom.uuid }
  let(:origin) { 'https://broker.disposable-mail.invalid' }
  let(:conversation) { create(:conversation, account: sd_account, inbox: inbox, contact: sd_contact, assignee: sd_user) }
  let(:binding) { JrcBrokerInboxBinding.create!(account: sd_account, inbox: inbox, integration_id: integration_id, instance_id: SecureRandom.uuid) }
  let(:headers) { sd_user.create_new_auth_token }

  around do |example|
    with_modified_env(JRC_BROKER_ENABLED: 'true', JRC_BROKER_ALLOWED_ORIGINS: origin) { example.run }
  end

  before do
    sd_account.enable_features!('jrc_broker')
    store = JrcBroker::CredentialStore.new(key: 'x' * 32)
    JrcBrokerIntegration.create!(account: sd_account, broker_origin: origin, organization_id: SecureRandom.uuid,
                                 destination_revision: 1, encrypted_control_key: store.encrypt(account_id: sd_account.id, token: 'synthetic-only'))
    binding
    channel.update!(webhook_url: "#{origin}/v1/integrations/chatwoot/#{integration_id}/events")
    allow(Resolv).to receive(:getaddresses).with('broker.disposable-mail.invalid').and_return(['93.184.216.34'])
  end

  it 'returns the bound Broker box as WhatsApp through real HTTP without credentials or a network request' do
    get "#{survey_url}/options", params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('inboxes')).to include(include('id' => inbox.id, 'channel' => 'whatsapp'))
    expect(response.body).not_to include('synthetic-only', channel.secret, 'encrypted_control_key')
    expect(WebMock).not_to have_requested(:any, /broker/)
  end

  it 'does not offer arbitrary API boxes or stale callbacks' do
    generic = create(:channel_api, account: sd_account).inbox
    channel.update!(webhook_url: "#{origin}/obsolete")
    choices = survey_editor.options(sd_unit.id).fetch(:inboxes)
    expect(choices.map { |row| row[:id] }).not_to include(inbox.id, generic.id)
  end

  it 'does not grant a Broker box through administrator privileges in another account' do
    other = create(:account)
    alien = create(:channel_api, account: other).inbox
    expect(survey_editor.options(sd_unit.id).fetch(:inboxes).map { |row| row[:id] }).not_to include(alien.id)
  end

  it 'requires explicit inbox membership for an agent even when it has a Broker binding' do
    sd_account_user.update!(role: :agent)
    expect(survey_editor.options(sd_unit.id).fetch(:inboxes).map { |row| row[:id] }).not_to include(inbox.id)
  end

  context 'published survey delivery' do
    let(:model_payload) do
      survey_payload.deep_dup.tap do |data|
        data['channels']['whatsapp'] = { 'enabled' => true, 'inbox_id' => inbox.id, 'message' => 'Synthetic survey: {{survey_link}}' }
        data['channels']['public_link']['enabled'] = false
      end
    end
    let(:ticket) { sd_ticket }
    let(:survey) do
      conversation
      publish_survey_model(model_payload)
      ticket.update!(status: create(:jrc_sd_status, unit: sd_unit, phase: 'closed', initial: false))
      decision = JrcRelationship::SurveyEngine.evaluate_event(source: ticket, event: 'closure', cycle_key: "broker:#{ticket.id}")
      expect(decision.state).to eq('scheduled'), decision.reason
      row = decision.survey
      JrcRelationship::SurveyDispatchJob.perform_now(row.id)
      row.reload
    end
    let(:message) { Message.find(survey.metadata.fetch('sent_message_id')) }
    let(:payload) { message.webhook_data.merge(event: 'message_created') }

    it 'persists and rereads the selected sender and enqueues one native message without sending at publication' do
      expect(message.inbox_id).to eq(inbox.id)
      expect(survey.status).to eq('queued')
      expect(message.content).to start_with('Synthetic survey: https://')
      expect(survey.rule_snapshot.dig('settings', 'delivery_inbox_id').to_s).to eq(inbox.id.to_s)
      expect(WebMock).not_to have_requested(:any, /broker/)
    end

    it 'does not consume the claim in SendReplyJob, sends once in the signed webhook and awaits a real receipt' do
      request = stub_request(:post, channel.webhook_url).to_return(status: 204)
      SendReplyJob.perform_now(message.id)
      expect(survey.reload.status).to eq('queued')
      2.times { WebhookJob.perform_now(channel.webhook_url, payload, :api_inbox_webhook, secret: channel.secret, delivery_id: 'synthetic-delivery') }
      expect(request).to have_been_requested.once
      expect(survey.reload.status).to eq('unknown')
      message.update!(source_id: 'synthetic-provider-id', status: :delivered)
      JrcRelationship::SurveyReceiptJob.perform_now(message.id)
      expect(survey.reload.status).to eq('delivered')
    end

    it 'blocks revoked consent immediately before webhook I/O' do
      message
      sd_contact.update!(custom_attributes: { survey_consent: false })
      request = stub_request(:post, channel.webhook_url).to_return(status: 204)
      WebhookJob.perform_now(channel.webhook_url, payload, :api_inbox_webhook, secret: channel.secret, delivery_id: 'synthetic-delivery')
      expect(request).not_to have_been_requested
      expect(survey.reload.status).to eq('blocked')
    end

    it 'blocks a deleted binding between enqueue and I/O without a provider call' do
      message
      binding.destroy!
      request = stub_request(:post, channel.webhook_url).to_return(status: 204)
      WebhookJob.perform_now(channel.webhook_url, payload, :api_inbox_webhook, secret: channel.secret, delivery_id: 'synthetic-delivery')
      expect(request).not_to have_been_requested
      expect(survey.reload.status).to eq('blocked')
    end

    it 'never blindly retries an uncertain provider result or exposes provider exception details' do
      request = stub_request(:post, channel.webhook_url).to_timeout
      2.times { WebhookJob.perform_now(channel.webhook_url, payload, :api_inbox_webhook, secret: channel.secret, delivery_id: 'synthetic-delivery') }
      expect(request).to have_been_requested.once
      expect(survey.reload.status).to eq('unknown')
      expect(survey.failure_code).to eq('provider_result_unknown')
    end
  end

  context 'transactional Service Desk notification through the same guarded Broker transport' do
    let(:sd_contact) { create(:contact, account: sd_account, phone_number: '+15555550142') }
    let(:ticket) { sd_ticket }
    let(:delivery) do
      create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
      JrcServiceDesk::PublishNotificationPolicyService.new(user_context: sd_context).call(unit_id: sd_unit.id,
                                                                                          attributes: { event_type: 'ticket_created', channel: 'whatsapp', enabled: true, confirmed: true, inbox_id: inbox.id,
                                                                                                        template: 'Synthetic transactional notification {{number}}', template_version: 'synthetic-v1', expected_version: 0 })
      event = create(:jrc_sd_event, ticket: ticket)
      JrcServiceDesk::NotificationEventJob.perform_now(event.id)
      row = JrcServiceDesk::NotificationDelivery.find_by!(ticket_event: event, channel: 'whatsapp')
      JrcServiceDesk::NotificationDeliveryJob.perform_now(row.id)
      expect(row.reload.state).to eq('queued'), row.reason
      expect(row.message).to be_present
      row.reload
    end

    it 'uses the chosen API inbox once at the signed webhook boundary without consuming a claim in SendReplyJob' do
      row = delivery
      message = row.message
      expect(message.inbox_id).to eq(inbox.id)
      request = stub_request(:post, channel.webhook_url).to_return(status: 204)
      SendReplyJob.perform_now(message.id)
      expect(row.reload.state).to eq('queued')
      2.times do
        WebhookJob.perform_now(channel.webhook_url, message.webhook_data.merge(event: 'message_created'), :api_inbox_webhook, secret: channel.secret,
                                                                                                                              delivery_id: 'synthetic-sd-notification')
      end
      expect(request).to have_been_requested.once
      expect(row.reload.state).to eq('unknown')
    end

    it 'blocks the native transactional notification before webhook I/O after recipient preference is revoked' do
      row = delivery
      sd_contact.update!(custom_attributes: sd_contact.custom_attributes.merge('service_desk_notification_channels' => []))
      request = stub_request(:post, channel.webhook_url).to_return(status: 204)
      WebhookJob.perform_now(channel.webhook_url, row.message.webhook_data.merge(event: 'message_created'), :api_inbox_webhook,
                             secret: channel.secret, delivery_id: 'synthetic-sd-revoked')
      expect(request).not_to have_been_requested
      expect(row.reload.state).to eq('blocked')
    end
  end
end

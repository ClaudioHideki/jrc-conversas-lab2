require 'rails_helper'

RSpec.describe JrcBroker::WebhookDelivery do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :resolved) }
  let(:survey) { MessageTemplates::Template::CsatSurvey.new(conversation: conversation).perform }
  let(:payload) { survey.webhook_data.merge(event: 'message_created') }

  before do
    JrcBrokerIntegration.create!(account: account, broker_origin: 'https://broker.example.test', organization_id: SecureRandom.uuid,
                                 destination_revision: 1, encrypted_control_key: 'synthetic-not-used')
    JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid)
  end

  it 'applies the Broker delivery boundary to a native CSAT template' do
    expect(described_class.for(payload, :api_inbox_webhook)).to be_a(described_class)
  end

  it 'rejects a wrong callback secret for native CSAT before HTTP' do
    allow(SafeFetch).to receive(:fetch)

    expect do
      Webhooks::Trigger.execute(inbox.channel.webhook_url, payload, :api_inbox_webhook,
                                secret: 'synthetic-wrong-secret', delivery_id: SecureRandom.uuid, strict: true)
    end.to raise_error(JrcBroker::WebhookDelivery::ContextChanged)
    expect(SafeFetch).not_to have_received(:fetch)
    expect(conversation.reload).to be_resolved
  end

  it 'does not admit a non-CSAT template through the new boundary' do
    message = Message.create!(account: account, inbox: inbox, conversation: conversation, message_type: :template, content_type: :text)

    expect(described_class.for(message.webhook_data.merge(event: 'message_created'), :api_inbox_webhook)).to be_nil
  end

  it 'does not admit a bot-authored CSAT template through the new boundary' do
    bot = create(:agent_bot, account: account)
    message = Message.create!(account: account, inbox: inbox, conversation: conversation,
                              message_type: :template, content_type: :input_csat, sender: bot)

    expect(described_class.for(message.webhook_data.merge(event: 'message_created'), :api_inbox_webhook)).to be_nil
  end
end

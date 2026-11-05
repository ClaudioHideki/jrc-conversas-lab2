require 'rails_helper'

RSpec.describe CsatSurveyService do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :resolved) }

  before { inbox.update!(csat_survey_enabled: true, csat_config: { 'message' => 'Synthetic survey' }) }

  it 'keeps one survey across repeated resolution events, reopening and another closure' do
    event = Events::Base.new('conversation.status_changed', Time.current, conversation: conversation)
    2.times { CsatSurveyListener.instance.conversation_status_changed(event) }
    conversation.update!(status: :open)
    CsatSurveyListener.instance.conversation_status_changed(event)
    conversation.update!(status: :resolved)
    CsatSurveyListener.instance.conversation_status_changed(event)

    expect(conversation.messages.where(content_type: :input_csat).count).to eq(1)
    expect(conversation.reload).to be_resolved
  end

  it 'allows one survey for each conversation belonging to the same contact' do
    other = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :resolved)

    [conversation, other].each { |value| described_class.new(conversation: value).perform }

    expect(conversation.messages.where(content_type: :input_csat).count).to eq(1)
    expect(other.messages.where(content_type: :input_csat).count).to eq(1)
  end

  it 'preserves the current permissive contract for an empty legacy label rule' do
    # An empty label rule currently matches every eligible conversation; it does
    # not demonstrate equivalence to any customer-specific legacy automation.
    inbox.update!(csat_config: { 'survey_rules' => { 'operator' => 'contains', 'values' => [] } })
    conversation.update!(label_list: ['synthetic-unrelated-label'])

    expect { described_class.new(conversation: conversation).perform }
      .to change { conversation.messages.where(content_type: :input_csat).count }.by(1)
  end

  it 'exposes a conversation-scoped HTTPS link and admits native transport through the bot guard' do
    with_modified_env(FRONTEND_URL: 'https://hml.example.test') do
      described_class.new(conversation: conversation).perform
      message = conversation.messages.find_by!(content_type: :input_csat)
      expect(message.webhook_data).to include(
        message_type: 'template', content_type: 'input_csat', sender: nil,
        content: "Synthetic survey https://hml.example.test/survey/responses/#{conversation.uuid}"
      )
      expect(message.sender_type).to be_nil
      JrcFlowOwnershipScope.create!(
        scope_key: JrcFlows::OwnershipGuard.key('https://hml.example.test', account.id, inbox.id),
        host_origin: 'https://hml.example.test', account_id: account.id, inbox_id: inbox.id, state: 'FENCED'
      )
      delivered_payloads = []
      allow(SafeFetch).to receive(:fetch) { |_url, **options| delivered_payloads << JSON.parse(options.fetch(:body)) }
      WebhookJob.perform_now(inbox.channel.webhook_url, message.webhook_data.merge(event: 'message_created'), :api_inbox_webhook,
                             secret: inbox.channel.secret, delivery_id: SecureRandom.uuid)
      expect(delivered_payloads.map { |payload| payload['content'] })
        .to eq(["Synthetic survey https://hml.example.test/survey/responses/#{conversation.uuid}"])
      expect(conversation.reload).to be_resolved
    end
  end
end

require 'rails_helper'

RSpec.describe 'WhatsApp templates selected from contacts', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:template) do
    { name: 'reativacao_cliente_01', language: 'pt_BR', category: 'MARKETING', processed_params: { body: { '1' => 'Synthetic' } } }
  end

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    channel.update!(message_templates: [{ name: 'reativacao_cliente_01', language: 'pt_BR', status: 'APPROVED', category: 'MARKETING',
                                         components: [{ type: 'BODY', text: 'Synthetic {{1}}' }] }])
    clear_enqueued_jobs
  end

  it 'persists and sends all 20 independent contacts with distinct correlations and delivered callbacks' do
    destinations = []
    transport = stub_request(:post, 'https://graph.facebook.com/v13.0/123456789/messages').to_return do |request|
      body = JSON.parse(request.body)
      expect(body.dig('template', 'name')).to eq('reativacao_cliente_01')
      expect(body.dig('template', 'language', 'code')).to eq('pt_BR')
      expect(body.dig('template', 'components', 0, 'parameters', 0, 'text')).to eq('Synthetic')
      destinations << body.fetch('to')
      { status: 200, body: { messages: [{ id: "wamid.synthetic-batch-#{destinations.length}" }] }.to_json,
        headers: { 'Content-Type' => 'application/json' } }
    end
    contacts = create_list(:contact, 20, :with_phone_number, account: account)
    headers = agent.create_new_auth_token
    perform_enqueued_jobs(only: SendReplyJob) do
      contacts.each do |contact|
        post "/api/v1/accounts/#{account.id}/conversations", headers: headers,
             params: { inbox_id: inbox.id, contact_id: contact.id, assignee_id: agent.id,
                       message: { content: 'Synthetic batch', template_params: template } }, as: :json
        expect(response).to have_http_status(:success)
      end
    end

    messages = inbox.messages.outgoing.order(:id).to_a
    expect(messages.size).to eq(20)
    expect(destinations.sort).to eq(contacts.map { |contact| contact.phone_number.delete('+') }.sort)
    expect(messages.map { |message| message.conversation.contact_id }.sort).to eq(contacts.map(&:id).sort)
    expect(messages.map(&:source_id).uniq.size).to eq(20)
    expect(messages.map(&:source_id)).to all(be_present)
    expect(transport).to have_been_requested.times(20)
    messages.each do |message|
      destination = message.conversation.contact.phone_number.delete('+')
      expect(message.source_id).to eq("wamid.synthetic-batch-#{destinations.index(destination) + 1}")
      SendReplyJob.perform_now(message.id)
      callback = { entry: [{ changes: [{ value: { statuses: [{ id: message.source_id, status: 'delivered' }] } }] }] }.with_indifferent_access
      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: callback).perform
    end
    expect(inbox.messages.outgoing.where(status: :delivered).count).to eq(20)
    expect(transport).to have_been_requested.times(20)
  end

  it 'accounts for all 20 when Meta rejects three deliveries and blocks misleading retries' do
    submitted = 0
    transport = stub_request(:post, 'https://graph.facebook.com/v13.0/123456789/messages').to_return do
      submitted += 1
      { status: 200, body: { messages: [{ id: "wamid.synthetic-mixed-#{submitted}" }] }.to_json,
        headers: { 'Content-Type' => 'application/json' } }
    end
    contacts = create_list(:contact, 20, :with_phone_number, account: account)
    headers = agent.create_new_auth_token
    perform_enqueued_jobs(only: SendReplyJob) do
      contacts.each do |contact|
        post "/api/v1/accounts/#{account.id}/conversations", headers: headers,
             params: { inbox_id: inbox.id, contact_id: contact.id, assignee_id: agent.id,
                       message: { content: 'Synthetic mixed batch', template_params: template } }, as: :json
        expect(response).to have_http_status(:success)
      end
    end
    messages = inbox.messages.outgoing.order(:id).to_a
    expect(messages.size).to eq(20)
    messages.each_with_index do |message, index|
      status = { id: message.source_id, status: index < 3 ? 'failed' : 'delivered' }
      status[:errors] = [{ code: index.zero? ? 131026 : 131049, title: 'Synthetic restriction' }] if index < 3
      callback = { entry: [{ changes: [{ value: { statuses: [status] } }] }] }.with_indifferent_access
      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: callback).perform
    end
    expect(inbox.messages.outgoing.where(status: :delivered).count).to eq(17)
    expect(inbox.messages.outgoing.where(status: :failed).count).to eq(3)
    messages.first(3).each do |message|
      original = message.reload.attributes.deep_dup
      post "/api/v1/accounts/#{account.id}/conversations/#{message.conversation.display_id}/messages/#{message.id}/retry",
           headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(message.reload.attributes).to eq(original)
      expect(message.external_error).to match(/131026|131049/)
    end
    expect(transport).to have_been_requested.times(20)
    expect(WhatsappRetryAttempt.where(original_message: messages)).not_to exist
  end
end

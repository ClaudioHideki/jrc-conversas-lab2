require 'rails_helper'

RSpec.describe 'CRM proposal delivery to a selected recipient', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:headers) { agent.create_new_auth_token }
  let(:company) { account.master_companies.create!(name: 'Empresa de teste de propostas') }
  let(:recipient) { create(:contact, account: account, name: 'Destinatária de teste', phone_number: '+5511998765432') }
  let(:inbox) { create(:inbox, account: account, name: 'WhatsApp de teste', channel: build(:channel_api, account: account)) }
  let(:product) { JrcCrm::Product.create!(account: account, name: 'Serviço de teste', sku: 'RECIPIENT-01', unit_price_cents: 10_000) }
  let(:proposal) { JrcCrm::ProposalBuilderService.new(actor: agent, account: account, company: company).call }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/proposals/#{proposal.id}/send_proposal" }
  let(:key) { SecureRandom.uuid }
  let(:delivery) { { contact_id: recipient.id, inbox_id: inbox.id, content: 'Segue a proposta solicitada.' } }
  let(:payload) { { channel: 'whatsapp', delivery: delivery, idempotency_key: key } }

  before do
    account.enable_features!('jrc_crm', 'jrc_customer_master')
    create(:inbox_member, inbox: inbox, user: agent)
    proposal.proposal_items.create!(product: product, name_snapshot: product.name, quantity: 1, unit_price_cents: 10_000)
  end

  it 'creates a native conversation, attaches the real PDF and preserves the proposal customer and deal' do
    expect { post url, params: payload, headers: headers, as: :json }.to change(Conversation, :count).by(1)
    expect(response).to have_http_status(:ok), response.body
    proposal.reload
    conversation = Conversation.find(proposal.last_sent_conversation_id)
    message = Message.find(proposal.last_sent_message_id)
    expect(conversation).to have_attributes(account_id: account.id, contact_id: recipient.id, inbox_id: inbox.id, assignee_id: agent.id)
    expect([message.content, message.attachments.first.file.download]).to match(
      [a_string_including('/jrc/propostas/', 'Segue a proposta solicitada.'), a_string_starting_with('%PDF-')]
    )
    expect(proposal).to have_attributes(status: 'sent', company_id: company.id, contact_id: nil, deal_id: nil)
    expect(recipient.reload.company_id).to be_nil
    expect(proposal.events.find_by!(event_type: 'sent').metadata).to include('recipient_contact_id' => recipient.id, 'delivery_key' => key)
  end

  it 'reuses an authorized open conversation in the selected inbox' do
    conversation = create(:conversation, account: account, inbox: inbox, contact: recipient, assignee: agent)
    expect { post url, params: payload, headers: headers, as: :json }.not_to change(Conversation, :count)
    expect(response).to have_http_status(:ok), response.body
    expect(proposal.reload.last_sent_conversation_id).to eq(conversation.id)
  end

  it 'replays the same intent without another message, PDF or sent event' do
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:ok), response.body
    message_id = proposal.reload.last_sent_message_id
    counts = [Message.count, Attachment.count, ActiveStorage::Blob.count, JrcCrm::ProposalEvent.count, Conversation.count]
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.dig('delivery', 'message_id')).to eq(message_id)
    expect([Message.count, Attachment.count, ActiveStorage::Blob.count, JrcCrm::ProposalEvent.count, Conversation.count]).to eq(counts)
  end

  it 'rejects changing the recipient under a previously used key' do
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:ok), response.body
    other = create(:contact, account: account, phone_number: '+5511998765433')
    changed = payload.deep_dup
    changed[:delivery][:contact_id] = other.id
    expect { post url, params: changed, headers: headers, as: :json }.not_to change(Message, :count)
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['code']).to eq('IDEMPOTENCY_CONTENT_CONFLICT')
  end

  it 'rejects a contact from another account without creating a conversation' do
    delivery[:contact_id] = create(:contact, phone_number: '+5511998765440').id
    expect { post url, params: payload, headers: headers, as: :json }.not_to change(Conversation, :count)
    expect(response).to have_http_status(:not_found)
    expect(proposal.reload.sent_at).to be_nil
  end

  it 'rejects an inbox from another account' do
    delivery[:inbox_id] = create(:inbox, name: 'WhatsApp externo').id
    expect { post url, params: payload, headers: headers, as: :json }.not_to change(Message, :count)
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects an inbox the actor cannot use even if the actor owns the proposal' do
    InboxMember.where(inbox: inbox, user: agent).delete_all
    expect { post url, params: payload, headers: headers, as: :json }.not_to change(Conversation, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects CRM-only custom roles without contact permission' do
    role = create(:custom_role, account: account, permissions: %w[jrc_crm conversation_manage])
    account.account_users.find_by!(user: agent).update!(custom_role: role)
    expect { post url, params: payload, headers: headers, as: :json }.not_to change(Message, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects custom roles without conversation permission and rolls back the new conversation' do
    role = create(:custom_role, account: account, permissions: %w[jrc_crm contact_manage])
    account.account_users.find_by!(user: agent).update!(custom_role: role)
    counts = [Conversation.count, ContactInbox.count, Message.count]
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect([Conversation.count, ContactInbox.count, Message.count]).to eq(counts)
  end

  it 'rejects a blocked recipient' do
    recipient.update!(blocked: true)
    expect { post url, params: payload, headers: headers, as: :json }.not_to change(Message, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rejects a recipient without a phone number' do
    recipient.update!(phone_number: nil)
    expect { post url, params: payload, headers: headers, as: :json }.not_to change(Conversation, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rechecks inbox access before replaying an already delivered intent' do
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:ok), response.body
    InboxMember.where(inbox: inbox, user: agent).delete_all
    expect { post url, params: payload, headers: headers, as: :json }.not_to change(Message, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects a proposal owned by another agent through direct API requests' do
    proposal.update!(owner: create(:user, account: account, role: :agent))
    expect { post url, params: payload, headers: headers, as: :json }.not_to change(Message, :count)
    expect(response).to have_http_status(:not_found)
  end

  it 'does not create a conversation or upload a PDF while approvals are pending' do
    proposal.update!(approval_status: 'pending', commercial_approval_status: 'pending')
    counts = [Conversation.count, ContactInbox.count, ActiveStorage::Blob.count]
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect([Conversation.count, ContactInbox.count, ActiveStorage::Blob.count]).to eq(counts)
  end

  it 'blocks closed proposals before creating any outgoing message' do
    proposal.update!(status: 'canceled')
    expect { post url, params: payload, headers: headers, as: :json }.not_to change(Message, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'requires a valid intent key for the new delivery flow' do
    expect { post url, params: payload.except(:idempotency_key), headers: headers, as: :json }.not_to change(Conversation, :count)
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['code']).to eq('IDEMPOTENCY_KEY_REQUIRED')
  end

  it 'does not silently use the legacy conversation when the selected-recipient payload is empty' do
    expect { post url, params: payload.merge(delivery: {}), headers: headers, as: :json }.not_to change(Message, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'allows the existing send button to reuse the recorded recipient without linking a customer' do
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:ok), response.body
    conversation_id = proposal.reload.last_sent_conversation_id
    expect { post url, params: { channel: 'whatsapp' }, headers: headers, as: :json }.to change(Message, :count).by(1)
    expect(response).to have_http_status(:ok), response.body
    expect(proposal.reload.last_sent_conversation_id).to eq(conversation_id)
    expect(proposal.contact_id).to be_nil
  end

  context 'when the selected inbox is an official WhatsApp channel' do
    let(:inbox) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', message_templates: templates,
                                sync_templates: false, validate_provider_config: false).inbox
    end
    let(:templates) do
      [{ 'name' => 'proposal_test', 'language' => 'pt_BR', 'status' => 'APPROVED',
         'components' => [{ 'type' => 'BODY', 'text' => 'Sua proposta: {{1}}' }] }]
    end
    let(:template_params) do
      token = CGI.escape(JrcCrm::Proposal.find(proposal.id).public_token)
      { name: 'proposal_test', language: 'pt_BR',
        processed_params: { body: { '1' => "http://www.example.com/jrc/propostas/#{account.id}/#{token}" } } }
    end

    it 'requires a template outside the reply window and rolls back the temporary conversation' do
      counts = [Conversation.count, ContactInbox.count, ActiveStorage::Blob.count]
      post url, params: payload, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors'].join).to include('modelo WhatsApp aprovado')
      expect([Conversation.count, ContactInbox.count, ActiveStorage::Blob.count]).to eq(counts)
    end

    it 'queues an approved template with the authoritative proposal URL and preserves the PDF in history' do
      delivery[:template_params] = template_params
      post url, params: payload, headers: headers, as: :json
      expect(response).to have_http_status(:ok), response.body
      message = Message.find(proposal.reload.last_sent_message_id)
      expect(message.additional_attributes.dig('template_params', 'processed_params', 'body', '1'))
        .to eq(template_params[:processed_params][:body]['1'])
      expect(message.attachments.first.file.download).to start_with('%PDF-')
      expect(message.conversation.can_reply?).to be(false)
    end

    it 'sends a free-form proposal within an existing technical reply window' do
      conversation = create(:conversation, account: account, inbox: inbox, contact: recipient, assignee: agent)
      create(:message, conversation: conversation, account: account, message_type: :incoming)
      expect { post url, params: payload, headers: headers, as: :json }.to change(Message, :count).by(1)
      expect(response).to have_http_status(:ok), response.body
      expect(proposal.reload.last_sent_conversation_id).to eq(conversation.id)
    end

    it 'accepts a document template carrying the authoritative public PDF URL' do
      document_template = { 'name' => 'proposal_test', 'language' => 'pt_BR', 'status' => 'APPROVED',
                            'components' => [{ 'type' => 'HEADER', 'format' => 'DOCUMENT' }, { 'type' => 'BODY', 'text' => 'Sua proposta' }] }
      inbox.channel.update!(message_templates: [document_template])
      header = { media_url: "#{template_params[:processed_params][:body]['1']}/pdf", media_type: 'document' }
      delivery[:template_params] = template_params.except(:processed_params).merge(processed_params: { header: header })
      post url, params: payload, headers: headers, as: :json
      expect(response).to have_http_status(:ok), response.body
      message = Message.find(proposal.reload.last_sent_message_id)
      expect(message.additional_attributes.dig('template_params', 'processed_params', 'header', 'media_url'))
        .to end_with('/pdf')
    end

    it 'rejects a template that does not actually send the proposal URL despite a misleading message preview' do
      delivery[:template_params] = template_params.deep_merge(processed_params: { body: { '1' => 'Outro conteúdo' } })
      delivery[:content] = template_params[:processed_params][:body]['1']
      expect { post url, params: payload, headers: headers, as: :json }.not_to change(Message, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors'].join).to include('link desta proposta')
    end

    it 'rejects templates that have not been approved' do
      inbox.channel.update!(message_templates: templates.map { |template| template.merge('status' => 'REJECTED') })
      delivery[:template_params] = template_params
      expect { post url, params: payload, headers: headers, as: :json }.not_to change(Message, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors'].join).to include('modelo WhatsApp aprovado')
    end
  end
end

require 'rails_helper'

RSpec.describe 'JRC conversation effects protocol 2', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account) }
  let(:headers) { { 'api_access_token' => admin.access_token.token } }
  let(:base) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/jrc_flow_effects" }
  let(:input) do
    { organization_id: SecureRandom.uuid, operation_id: SecureRandom.uuid, dispatch_proof: SecureRandom.uuid,
      inbox_id: conversation.inbox_id.to_s, remote_contact_id: conversation.contact_id.to_s,
      expected_control_revision: conversation.reload.attributes.fetch('jrc_effect_control_revision', 0).to_s,
      operation: 'note', value_json: '"Internal note"' }
  end

  it 'advertises all four operations and a scoped monotonic context' do
    get "/api/v1/accounts/#{account.id}/jrc_flow_effects/capabilities", params: { inbox_id: conversation.inbox_id }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('protocol' => 'jrc-conversation-effects/2', 'operations' => %w[tag attribute note resolve])
    get "#{base}/context", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('contact_inbox_id' => conversation.contact_inbox_id,
                                            'remote_contact_id' => conversation.contact_id,
                                            'routing_source_hash' => Digest::SHA256.hexdigest(conversation.contact_inbox.source_id))
  end

  it 'creates one attributed private message and a receipt for its control revision' do
    params = input
    expect { post base, params: params, headers: headers, as: :json }.to change(Message, :count).by(1)
    expect(response).to have_http_status(:ok)
    receipt = response.parsed_body
    expect(receipt).to include('state' => 'CONFIRMED', 'control_revision_before' => params[:expected_control_revision].to_i,
                               'actor_user_id' => admin.id)
    expect(receipt['control_revision_after']).to be > receipt['control_revision_before']
    message = Message.find(receipt.fetch('message_id'))
    expect(message).to be_private
    expect(message.sender).to eq(admin)
  end

  it 'recovers a lost response without another message and rejects a changed body' do
    params = input
    post base, params: params, headers: headers, as: :json
    receipt = response.parsed_body
    expect { post base, params: params, headers: headers, as: :json }.not_to change(Message, :count)
    expect(response.parsed_body).to eq(receipt)
    get "#{base}/#{params[:operation_id]}", params: params.slice(:organization_id, :dispatch_proof), headers: headers
    expect(response.parsed_body).to eq(receipt)
    post base, params: params.merge(value_json: '"Different"'), headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
  end

  it 'rejects a stale human revision without creating a message' do
    params = input
    conversation.update_column(:status, 1) # rubocop:disable Rails/SkipsModelValidations -- Prove SQL paths bypassing callbacks retain the guard.
    expect { post base, params: params, headers: headers, as: :json }.not_to change(Message, :count)
    expect(response).to have_http_status(:conflict)
  end

  it 'rejects a changed recipient source without creating a message' do
    params = input
    conversation.contact_inbox.update_column(:source_id, SecureRandom.uuid) # rubocop:disable Rails/SkipsModelValidations -- Prove SQL paths bypassing callbacks retain the guard.
    expect { post base, params: params, headers: headers, as: :json }.not_to change(Message, :count)
    expect(response).to have_http_status(:conflict)
  end

  it 'resolves explicitly with an authenticated durable receipt' do
    post base, params: input.merge(operation: 'resolve', value_json: '"RESOLVED"'), headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(conversation.reload).to be_resolved
    expect(response.parsed_body).to include('operation' => 'resolve', 'state' => 'CONFIRMED', 'message_id' => nil)
  end

  it 'preserves the existing inbound reopen policy without replaying the resolved effect' do
    params = input.merge(operation: 'resolve', value_json: '"RESOLVED"')
    post base, params: params, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    receipt = response.parsed_body
    create(:message, conversation: conversation.reload, account: account, inbox: conversation.inbox,
                     sender: conversation.contact, message_type: :incoming)
    expect(conversation.reload).to be_open
    post base, params: params, headers: headers, as: :json
    expect(response.parsed_body).to eq(receipt)
    expect(conversation.reload).to be_open
  end

  it 'refuses browser sessions and ordinary agents' do
    post base, params: input, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    agent = create(:user, account: account, role: :agent)
    post base, params: input, headers: { 'api_access_token' => agent.access_token.token }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'adds one label and merges one typed attribute while preserving unrelated edits' do
    label = create(:label, account: account, title: 'flow-label')
    definition = create(:custom_attribute_definition, account: account, attribute_model: 'conversation_attribute',
                                                      attribute_display_type: 'checkbox', attribute_key: 'approved')
    conversation.update!(custom_attributes: { 'human_key' => 'keep' }, label_list: ['human-label'])
    get "/api/v1/accounts/#{account.id}/jrc_flow_effects/capabilities", params: { inbox_id: conversation.inbox_id }, headers: headers
    catalogue = response.parsed_body.fetch('resources')
    resource = catalogue.find { |item| item['kind'] == 'LABEL' && item['id'] == label.id }
    post base, params: input.merge(operation: 'tag', resource_id: label.id.to_s, resource_revision: resource['revision'], value_json: 'null'),
               headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(conversation.reload.label_list).to contain_exactly('human-label', 'flow-label')
    resource = catalogue.find { |item| item['kind'] == 'ATTRIBUTE' && item['id'] == definition.id }
    attribute_input = input.merge(operation_id: SecureRandom.uuid, expected_control_revision: conversation.jrc_effect_control_revision.to_s,
                                  operation: 'attribute', resource_id: definition.id.to_s,
                                  resource_revision: resource['revision'], value_json: 'false')
    post base, params: attribute_input,
               headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(conversation.reload.custom_attributes).to include('human_key' => 'keep', 'approved' => false)
  end

  it 'does not accept self-declared proof for another account or conversation' do
    params = input
    post base, params: params, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    other = create(:conversation, account: account)
    path = "/api/v1/accounts/#{account.id}/conversations/#{other.display_id}/jrc_flow_effects/#{params[:operation_id]}"
    get path, params: params.slice(:organization_id, :dispatch_proof), headers: headers
    expect(response).to have_http_status(:not_found)
    get "#{base}/#{params[:operation_id]}", params: params.slice(:organization_id).merge(dispatch_proof: SecureRandom.uuid), headers: headers
    expect(response).to have_http_status(:conflict)
  end

  it 'rejects invalid decimal IDs, composite values and a changed contact' do
    params = input
    [params.merge(inbox_id: "0#{conversation.inbox_id}"), params.merge(remote_contact_id: '9007199254740992'),
     params.merge(value_json: '{"text":"bad"}'), params.merge(value_json: '["bad"]'),
     params.merge(remote_contact_id: create(:contact, account: account).id.to_s)].each do |invalid|
      expect { post base, params: invalid, headers: headers, as: :json }.not_to change(Message, :count)
      expect(response).to have_http_status(:conflict)
    end
  end

  it 'makes receipt identity and proof immutable even through SQL updates' do
    params = input
    post base, params: params, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    receipt = JrcFlowEffectReceipt.find_by!(operation_id: params[:operation_id])
    expect do
      JrcFlowEffectReceipt.transaction(requires_new: true) do
        receipt.update_columns(request_hash: '0' * 64, message_id: nil) # rubocop:disable Rails/SkipsModelValidations -- Prove SQL paths bypassing callbacks retain the guard.
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    expect(receipt.reload.message_id).to be_present
  end

  it 'binds a replay to the authenticated User, not a submitted actor field' do
    params = input
    post base, params: params, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    second = create(:user, account: account, role: :administrator)
    post base, params: params.merge(actor_user_id: admin.id), headers: { 'api_access_token' => second.access_token.token }, as: :json
    expect(response).to have_http_status(:conflict)
  end

  it 'rolls back the action if its receipt cannot commit' do
    allow(JrcFlowEffectReceipt).to receive(:create!).and_raise(RuntimeError, 'simulated receipt storage failure')
    post base, params: input, headers: headers, as: :json
    expect(response).to have_http_status(:internal_server_error)
    expect(JrcFlowEffectReceipt).to have_received(:create!)
    expect(conversation.messages.where(private: true, content: 'Internal note')).to be_empty
  end

  it 'advertises no operations when a required database trigger is disabled' do
    ActiveRecord::Base.connection.execute('ALTER TABLE messages DISABLE TRIGGER jrc_effect_message_control')
    get "/api/v1/accounts/#{account.id}/jrc_flow_effects/capabilities", params: { inbox_id: conversation.inbox_id }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('operations' => [], 'control_revision_supported' => false)
    expect { post base, params: input, headers: headers, as: :json }.not_to change(Message, :count)
    expect(response).to have_http_status(:conflict)
  ensure
    ActiveRecord::Base.connection.execute('ALTER TABLE messages ENABLE TRIGGER jrc_effect_message_control')
  end
end

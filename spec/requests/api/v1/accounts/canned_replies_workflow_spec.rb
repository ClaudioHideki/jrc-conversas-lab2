require 'rails_helper'

RSpec.describe 'Contextual quick replies', type: :request do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let(:agent) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, name: 'Cliente Teste', additional_attributes: { city: 'São Paulo', region: 'Sudeste' }) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:canned) { create(:canned_response, account: account, short_code: 'contexto', content: 'Olá [nome], sou [vendedor]. [empresa] [cidade] [região] [produto/serviço] [data]') }
  let(:base) { "/api/v1/accounts/#{account.id}/canned_responses" }
  let(:headers) { agent.create_new_auth_token }

  it 'resolves the current sender, location and configured timezone without inventing missing data' do
    travel_to Time.utc(2026, 11, 15, 1, 0) do
      post "#{base}/#{canned.id}/preview", params: { conversation_id: conversation.display_id }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['content']).to include('Cliente Teste', agent.name, 'São Paulo', 'Sudeste', '[empresa]', '[produto/serviço]', '14/11/2026')
      expect(response.headers['Cache-Control']).to include('no-store')
    end
  end

  it 'uses the authenticated agent instead of the assigned agent' do
    assigned = create(:user, account: account)
    conversation.update!(assignee: assigned)
    post "#{base}/#{canned.id}/preview", params: { conversation_id: conversation.display_id }, headers: headers, as: :json
    expect(response.parsed_body['content']).to include(agent.name)
    expect(response.parsed_body['content']).not_to include(assigned.name)
  end

  it 'preserves the name placeholder for a contact without a name' do
    contact.update_columns(name: nil)
    post "#{base}/#{canned.id}/preview", params: { conversation_id: conversation.display_id }, headers: headers, as: :json
    expect(response.parsed_body['content']).to include('[nome]')
  end

  it 'uses an authorized master-company name and preserves the placeholder when corporate coverage denies it' do
    account.enable_features!('jrc_customer_master')
    company = JrcCustomers::Company.create!(account: account, name: 'Empresa Sintética', relationship_type: 'customer')
    contact.update!(company_id: company.id)
    post "#{base}/#{canned.id}/preview", params: { conversation_id: conversation.display_id }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['content']).to include('Empresa Sintética')
    company.update!(relationship_type: 'internal')
    post "#{base}/#{canned.id}/preview", params: { conversation_id: conversation.display_id }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['content']).to include('[empresa]')
    expect(response.parsed_body['content']).not_to include('Empresa Sintética')
  end

  it 'does not turn a structured or absent attribute into invented text' do
    contact.update!(additional_attributes: { city: { hidden: 'not a city' }, region: nil })
    post "#{base}/#{canned.id}/preview", params: { conversation_id: conversation.display_id }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['content']).to include('[cidade]', '[região]')
  end

  it 'limits the existing Liquid renderer without changing global limits' do
    canned.update!(content: '{% for i in (1..50000) %}x{% endfor %}')
    post "#{base}/#{canned.id}/preview", params: { conversation_id: conversation.display_id }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('RENDER_LIMIT')
  end

  it 'continues to resolve legacy Liquid templates with native drops' do
    canned.update!(content: 'Olá {{ contact.first_name }}. {{ agent.name }}')
    post "#{base}/#{canned.id}/preview", params: { conversation_id: conversation.display_id }, headers: headers, as: :json
    expect(response.parsed_body['content']).to include('Cliente', UserDrop.new(agent).name)
    expect(response.parsed_body['content']).not_to include('{{')
  end

  it 'does not mix two successive conversation contacts' do
    other = create(:conversation, account: account, contact: create(:contact, account: account, name: 'Outro Cliente'))
    [conversation, other].each do |current|
      post "#{base}/#{canned.id}/preview", params: { conversation_id: current.display_id }, headers: headers, as: :json
      expect(response.parsed_body['content']).to include(current.contact.name)
    end
  end

  it 'rejects a template from another account' do
    foreign = create(:canned_response)
    post "#{base}/#{foreign.id}/preview", params: { conversation_id: conversation.display_id }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'rechecks native conversation visibility instead of trusting its ID' do
    outsider = create(:user, account: account, role: :agent)
    post "#{base}/#{canned.id}/preview", params: { conversation_id: conversation.display_id }, headers: outsider.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'persists a native image attachment and exposes metadata without a signed storage URL' do
    post base, params: { canned_response: { short_code: 'image', content: 'Imagem', file: fixture_file_upload('spec/assets/sample.png', 'image/png') } }, headers: headers
    expect(response).to have_http_status(:ok)
    data = response.parsed_body
    expect(data['file']).to include('filename' => 'sample.png', 'content_type' => 'image/png')
    expect(data['file'].keys).not_to include('signed_id', 'url')
    get "#{base}/#{data['id']}/file", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'supports an authorized file replacement and removal' do
    canned.file.attach(io: File.open(Rails.root.join('spec/assets/sample.pdf')), filename: 'old.pdf', content_type: 'application/pdf')
    patch "#{base}/#{canned.id}", params: { canned_response: { file: fixture_file_upload('spec/assets/sample.png', 'image/png') } }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(canned.reload.file.filename.to_s).to eq('sample.png')
    patch "#{base}/#{canned.id}", params: { canned_response: { remove_file: true } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(canned.reload.file).not_to be_attached
  end

  it 'returns exactly the reviewed attachment and refuses replacements under a stale preview' do
    canned.file.attach(io: File.open(Rails.root.join('spec/assets/sample.pdf')), filename: 'reviewed.pdf', content_type: 'application/pdf')
    post "#{base}/#{canned.id}/preview", params: { conversation_id: conversation.display_id }, headers: headers, as: :json
    preview = response.parsed_body
    expected = { revision: preview.fetch('revision'), attachment_id: preview.fetch('file').fetch('id') }
    get "#{base}/#{canned.id}/file", params: expected, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body.b).to eq(File.binread(Rails.root.join('spec/assets/sample.pdf')))
    canned.file.attach(io: File.open(Rails.root.join('spec/assets/sample.png')), filename: 'replacement.png', content_type: 'image/png')
    get "#{base}/#{canned.id}/file", params: expected, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('RESPONSE_CHANGED')
    expect(conversation.messages.outgoing).to be_empty
  end

  it 'refuses a mismatched attachment ID even when the current revision matches' do
    canned.file.attach(io: File.open(Rails.root.join('spec/assets/sample.png')), filename: 'reviewed.png', content_type: 'image/png')
    get "#{base}/#{canned.id}/file", params: { revision: canned.reload.updated_at.iso8601(6), attachment_id: canned.file.id + 1 }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('RESPONSE_CHANGED')
  end

  it 'rejects HTML content and foreign signed blob references' do
    canned.file.attach(io: StringIO.new('<script>alert(1)</script>'), filename: 'bad.html', content_type: 'text/html')
    expect(canned).not_to be_valid
    patch "#{base}/#{canned.id}", params: { canned_response: { file: 'foreign-signed-id' } }, headers: headers, as: :json
    expect(response).to have_http_status(:bad_request)
  end

  it 'enforces the installation upload limit' do
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('MAXIMUM_FILE_UPLOAD_SIZE', 40).and_return(1)
    canned.file.attach(io: StringIO.new('x' * ((1024 * 1024) + 1)), filename: 'large.txt', content_type: 'text/plain')
    expect(canned).not_to be_valid
    expect(canned.errors[:file]).to include('size is too big')
  end

  it 'requires explicit confirmation and creates only one native message for repeated delivery' do
    values = { conversation_id: conversation.display_id, content: 'Texto revisado', delivery_key: 'synthetic-intent-1234', actor_id: agent.id, revision: canned.updated_at.iso8601(6) }
    post "#{base}/#{canned.id}/deliver", params: values.merge(confirmed: false), headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    2.times { post "#{base}/#{canned.id}/deliver", params: values.merge(confirmed: true), headers: headers, as: :json; expect(response).to have_http_status(:ok) }
    expect(conversation.messages.outgoing.where(content: 'Texto revisado').count).to eq(1)
    saved = conversation.messages.outgoing.find_by!(content: 'Texto revisado')
    expect(saved.reload.additional_attributes.dig('quick_reply', 'key')).to eq(values[:delivery_key])
    expect(saved.sender).to eq(agent)
  end

  it 'preserves the native WhatsApp text boundary before creating an outgoing quick reply' do
    whatsapp = create(:channel_whatsapp, account: account)
    conversation.update!(inbox: create(:inbox, account: account, channel: whatsapp))
    create(:message, conversation: conversation, message_type: :incoming)
    values = { conversation_id: conversation.display_id, confirmed: true, actor_id: agent.id,
               revision: canned.updated_at.iso8601(6), delivery_key: 'synthetic-channel-limit-1234' }
    post "#{base}/#{canned.id}/deliver", params: values.merge(content: 'x' * 4097), headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('CONTENT_TOO_LONG')
    expect(conversation.messages.outgoing).to be_empty
    post "#{base}/#{canned.id}/deliver", params: values.merge(content: 'x' * 4096), headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(conversation.messages.outgoing.sole.content.length).to eq(4096)
  end

  it 'refuses changed content under the same intent key and stale template revisions' do
    service = CannedResponses::Delivery.new(response: canned, conversation: conversation.reload, user: agent)
    values = { content: 'Original', key: 'synthetic-intent-4567', expected_actor_id: agent.id, confirmed: true, revision: canned.updated_at.iso8601(6) }
    service.call(**values)
    expect { service.call(**values.merge(content: 'Alterado')) }.to raise_error(CannedResponses::Delivery::Invalid, 'DELIVERY_CONTENT_CHANGED')
    expect { service.call(**values.merge(key: 'synthetic-intent-9876', revision: 'old')) }.to raise_error(CannedResponses::Delivery::Invalid, 'RESPONSE_CHANGED')
  end

  it 'does not create a message when the native WhatsApp window is closed' do
    conversation.reload
    allow(conversation).to receive(:can_reply?).and_return(false)
    expect do
      CannedResponses::Delivery.new(response: canned, conversation: conversation, user: agent).call(
        content: 'Revisado', key: 'synthetic-intent-closed', expected_actor_id: agent.id, confirmed: true, revision: canned.updated_at.iso8601(6)
      )
    end.to raise_error(CannedResponses::Delivery::Invalid, 'MESSAGE_WINDOW_CLOSED')
    expect(conversation.messages.outgoing).to be_empty
  end
  it 'rejects a preview made under another authenticated actor without creating a message' do
    post "#{base}/#{canned.id}/deliver", params: { conversation_id: conversation.display_id, content: 'Reviewed',
      confirmed: true, actor_id: agent.id + 100_000, delivery_key: 'synthetic-actor-changed', revision: canned.updated_at.iso8601(6) }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('ACTOR_CHANGED')
    expect(conversation.messages.outgoing).to be_empty
  end

  it 'treats alias values as data instead of executing embedded Liquid' do
    contact.update!(name: '{{ account.name }}')
    canned.update!(content: 'Nome: [nome]')
    post "#{base}/#{canned.id}/preview", params: { conversation_id: conversation.display_id }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['content']).to eq('Nome: {{ account.name }}')
  end

  it 'bounds alias expansion after Liquid even when the stored model is small' do
    contact.update!(name: 'x' * 255)
    canned.update!(content: '[nome]' * 300)
    post "#{base}/#{canned.id}/preview", params: { conversation_id: conversation.display_id }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('RENDER_LIMIT')
    expect(conversation.messages.outgoing).to be_empty
  end

  it 'delivers a real PDF with a separate native blob and no duplicate attachment on retry' do
    canned.file.attach(io: File.open(Rails.root.join('spec/assets/sample.pdf')), filename: 'synthetic.pdf', content_type: 'application/pdf')
    original = canned.reload.file.blob
    blobs_before = ActiveStorage::Blob.count
    values = { conversation_id: conversation.display_id, content: 'Documento revisado', confirmed: true, actor_id: agent.id,
               delivery_key: 'synthetic-pdf-copy-1234', revision: canned.updated_at.iso8601(6) }
    2.times do
      post "#{base}/#{canned.id}/deliver", params: values, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
    end
    expect(conversation.messages.outgoing.count).to eq(1)
    attachment = conversation.messages.outgoing.first.attachments.sole
    expect(attachment.file.blob_id).not_to eq(original.id)
    expect(attachment.file.download).to eq(original.download)
    expect(attachment).to be_file
    expect(ActiveStorage::Blob.count).to eq(blobs_before + 1)
  end

  it 'keeps the shared model readable when the sent copy becomes a protected Service Desk attachment' do
    canned.file.attach(io: File.open(Rails.root.join('spec/assets/sample.png')), filename: 'synthetic.png', content_type: 'image/png')
    ticket = create(:jrc_sd_ticket, account: account, unit: create(:jrc_sd_unit, operator_company: create(:jrc_sd_operator_company, account: account)))
    JrcServiceDesk::TicketConversation.create!(account: account, unit: ticket.unit, ticket: ticket,
      conversation: conversation, linked_by_membership: ticket.created_by_membership)
    values = { conversation_id: conversation.display_id, content: 'Imagem revisada', confirmed: true, actor_id: agent.id,
               delivery_key: 'synthetic-sd-copy-1234', revision: canned.reload.updated_at.iso8601(6) }
    post "#{base}/#{canned.id}/deliver", params: values, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    sent = conversation.messages.outgoing.first.attachments.sole.file.blob
    expect(JrcServiceDesk::ProtectedBlobAccess.new(blob: sent, user: nil)).to be_protected
    expect(JrcServiceDesk::ProtectedBlobAccess.new(blob: canned.file.blob, user: nil)).not_to be_protected
    other_member = create(:user, account: account, role: :agent)
    get "#{base}/#{canned.id}/file", headers: other_member.create_new_auth_token
    expect(response).to have_http_status(:ok)
  end

end

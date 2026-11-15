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
    values = { conversation_id: conversation.display_id, content: 'Texto revisado', delivery_key: 'synthetic-intent-1234', revision: canned.updated_at.iso8601(6) }
    post "#{base}/#{canned.id}/deliver", params: values.merge(confirmed: false), headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    2.times { post "#{base}/#{canned.id}/deliver", params: values.merge(confirmed: true), headers: headers, as: :json; expect(response).to have_http_status(:ok) }
    expect(conversation.messages.outgoing.where(content: 'Texto revisado').count).to eq(1)
  end

  it 'refuses changed content under the same intent key and stale template revisions' do
    service = CannedResponses::Delivery.new(response: canned, conversation: conversation, user: agent)
    values = { content: 'Original', key: 'synthetic-intent-4567', confirmed: true, revision: canned.updated_at.iso8601(6) }
    service.call(**values)
    expect { service.call(**values.merge(content: 'Alterado')) }.to raise_error(CannedResponses::Delivery::Invalid, 'DELIVERY_CONTENT_CHANGED')
    expect { service.call(**values.merge(key: 'synthetic-intent-9876', revision: 'old')) }.to raise_error(CannedResponses::Delivery::Invalid, 'RESPONSE_CHANGED')
  end

  it 'does not create a message when the native WhatsApp window is closed' do
    allow(conversation).to receive(:can_reply?).and_return(false)
    expect do
      CannedResponses::Delivery.new(response: canned, conversation: conversation, user: agent).call(
        content: 'Revisado', key: 'synthetic-intent-closed', confirmed: true, revision: canned.updated_at.iso8601(6)
      )
    end.to raise_error(CannedResponses::Delivery::Invalid, 'MESSAGE_WINDOW_CLOSED')
    expect(conversation.messages.outgoing).to be_empty
  end
end

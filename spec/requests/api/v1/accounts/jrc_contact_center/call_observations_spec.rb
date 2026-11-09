# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Contact Center call observations', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: agent) }
  let(:headers) { agent.create_new_auth_token }
  let(:call) do
    JrcContactCenter::CallSession.create!(account: account, provider: 'jrc_pabx', correlation_id: SecureRandom.uuid,
                                        direction: 'inbound', status: 'connected', started_at: Time.current,
                                        metadata: { 'retained' => 'synthetic', 'jrc_f1' => { 'internal' => true } })
  end
  let(:path) { "/api/v1/accounts/#{account.id}/jrc_contact_center/call_sessions/#{call.id}/observations" }

  before do
    account.enable_features!('jrc_contact_center')
    JrcContactCenter::CallLeg.create!(account: account, call_session: call, account_user: member,
                                    direction: 'inbound', status: 'connected', started_at: call.started_at)
  end

  it 'includes customer context in the authorized call even without a queue membership' do
    customer = create(:contact, account: account, phone_number: '+5511987650000')
    call.update!(contact: customer)

    get path.delete_suffix('/observations'), headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('item', 'customer', 'status')).to eq('identified')
    expect(response.parsed_body.dig('item', 'customer', 'contacts').pluck('id')).to eq([customer.id.to_s])
  end

  it 'resolves only the exact authorized provider session without listing another call' do
    call.update!(external_session_id: 'synthetic-sip-call')
    get path.delete_suffix("/#{call.id}/observations"),
        params: { external_session_id: 'does-not-exist', provider: 'jrc_pabx' }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to be_empty
  end

  it 'persists and reloads observations without changing call state, assignment or qualification' do
    patch path, params: { observations: { text: 'Retornar com o protocolo sintético.', lock_version: call.lock_version },
                         status: 'ended', account_id: create(:account).id }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(call.reload.status).to eq('connected')
    expect(call.metadata.fetch('retained')).to eq('synthetic')
    expect(call.metadata.dig('attendance_observations', 'text')).to eq('Retornar com o protocolo sintético.')
    expect(call.metadata.dig('attendance_observations', 'account_user_id')).to eq(member.id)
    expect(JrcContactCenter::Qualification.where(call_session: call)).to be_empty

    get path.delete_suffix('/observations'), headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('item', 'metadata', 'attendance_observations', 'text')).to eq('Retornar com o protocolo sintético.')
    expect(response.parsed_body.dig('item', 'attendant', 'name')).to eq(agent.name)
    expect(response.parsed_body.dig('item', 'metadata')).not_to have_key('jrc_f1')
  end

  it 'rejects stale versions and preserves the last saved note' do
    version = call.lock_version
    call.update!(metadata: call.metadata.merge('attendance_observations' => { 'text' => 'Outra edição' }))
    patch path, params: { observations: { text: 'Desatualizado', lock_version: version } }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(call.reload.metadata.dig('attendance_observations', 'text')).to eq('Outra edição')
  end

  it 'allows clearing a saved observation with the current version' do
    call.update!(metadata: call.metadata.merge('attendance_observations' => { 'text' => 'Limpar' }))
    patch path, params: { observations: { text: '', lock_version: call.lock_version } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(call.reload.metadata.dig('attendance_observations', 'text')).to eq('')
  end

  it 'rejects oversized notes and invalid versions without writing' do
    original = call.attributes
    patch path, params: { observations: { text: 'x' * 1001, lock_version: call.lock_version } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    patch path, params: { observations: { text: 'Texto', lock_version: 'invalid' } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(call.reload.attributes).to eq(original)
  end

  it 'rejects an agent assigned to a different call in the same Account' do
    other_agent = create(:user, account: account, role: :agent)
    original = call.attributes
    patch path, params: { observations: { text: 'Negado', lock_version: call.lock_version } },
                headers: other_agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    expect(call.reload.attributes).to eq(original)
  end

  it 'rejects another Account and unauthenticated requests without writing' do
    other_agent = create(:user, account: create(:account), role: :administrator)
    original = call.attributes
    patch path, params: { observations: { text: 'Negado', lock_version: call.lock_version } },
                headers: other_agent.create_new_auth_token, as: :json
    expect(response).not_to have_http_status(:ok)
    patch path, params: { observations: { text: 'Anônimo', lock_version: call.lock_version } }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(call.reload.attributes).to eq(original)
  end

  it 'requires the existing operate permission even when a custom role can view the call' do
    role = create(:custom_role, account: account, permissions: ['jrc_contact_center_view'])
    member.update!(custom_role: role)
    original = call.attributes
    patch path, params: { observations: { text: 'Negado', lock_version: call.lock_version } }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(call.reload.attributes).to eq(original)
  end

  it 'does not enable the module when it is disabled' do
    account.disable_features!('jrc_contact_center')
    original = call.attributes
    patch path, params: { observations: { text: 'Negado', lock_version: call.lock_version } }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(call.reload.attributes).to eq(original)
  end

  it 'keeps each saved revision including an intentional clear and paginates without overlap' do
    %w[Primeira Segunda].each do |text|
      patch path, params: { observations: { text: text, lock_version: call.reload.lock_version } }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
    end
    patch path, params: { observations: { text: '', lock_version: call.reload.lock_version } }, headers: headers, as: :json
    get path, params: { limit: 2 }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    first_page = response.parsed_body
    expect(first_page.fetch('items').pluck('text')).to eq(['', 'Segunda'])
    expect(first_page.fetch('items').pluck('author_user_id').uniq).to eq([agent.id])
    get path, params: { limit: 2, before_id: first_page.fetch('next_before_id') }, headers: headers, as: :json
    expect(response.parsed_body.fetch('items').pluck('text')).to eq(['Primeira'])
    expect(response.parsed_body['next_before_id']).to be_nil
  end

  it 'does not create a revision for a rejected stale write or an unchanged retry' do
    patch path, params: { observations: { text: 'Primeira', lock_version: call.lock_version } }, headers: headers, as: :json
    current_version = call.reload.lock_version
    patch path, params: { observations: { text: 'Primeira', lock_version: current_version } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(call.reload.lock_version).to eq(current_version)
    patch path, params: { observations: { text: 'Outra', lock_version: current_version - 1 } }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    get path, headers: headers, as: :json
    expect(response.parsed_body.fetch('items').pluck('text')).to eq(['Primeira'])
  end

  it 'denies observation history to an unassigned agent and another Account' do
    stranger = create(:user, account: account, role: :agent)
    outsider = create(:user, account: create(:account), role: :administrator)
    [[stranger, :not_found], [outsider, :unauthorized]].each do |user, status|
      get path, headers: user.create_new_auth_token, as: :json
      expect(response).to have_http_status(status)
    end
  end

  it 'does not expose private notes through a view-only call projection or history' do
    call.update!(metadata: call.metadata.merge('attendance_observations' => { 'text' => 'Privado' }))
    role = create(:custom_role, account: account, permissions: ['jrc_contact_center_view'])
    member.update!(custom_role: role)
    get path.delete_suffix('/observations'), headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('item', 'metadata')).not_to have_key('attendance_observations')
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
  end
end

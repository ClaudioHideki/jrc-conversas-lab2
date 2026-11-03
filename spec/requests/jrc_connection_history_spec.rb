require 'rails_helper'

RSpec.describe 'Broker connection history', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:url) { "/api/v1/accounts/#{account.id}/jrc_broker/inboxes/#{inbox.id}/history" }

  around { |example| with_modified_env(JRC_BROKER_ENABLED: 'true') { example.run } }
  before do
    account.enable_features!('jrc_broker')
    JrcBrokerIntegration.create!(account: account, broker_origin: 'https://broker.example.test', organization_id: SecureRandom.uuid,
                                destination_revision: 1, encrypted_control_key: 'synthetic-not-used')
    JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid)
  end

  it 'returns an empty authorized history without contacting the provider' do
    expect(JrcBroker::Client).not_to receive(:new)
    get url, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('data' => [], 'next_cursor' => nil)
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'paginates and filters stable events without skipping ties or disclosing another connection' do
    52.times do |index|
      JrcBrokerConnectionEvent.create!(account: account, inbox: inbox, user: admin, event_type: 'CONNECTED',
                                      occurred_at: Time.current, metadata: { result: index.to_s })
    end
    other = create(:channel_api, account: account).inbox
    JrcBrokerConnectionEvent.create!(account: account, inbox: other, event_type: 'DISCONNECTED', occurred_at: Time.current)
    get url, headers: admin.create_new_auth_token, params: { event_type: 'CONNECTED' }
    expect(response).to have_http_status(:ok)
    first = response.parsed_body
    expect(first['data'].size).to eq(50)
    get url, headers: admin.create_new_auth_token, params: { event_type: 'CONNECTED', before: first['next_cursor'] }
    expect(response.parsed_body['data'].size).to eq(2)
    expect(response.parsed_body['data'].pluck('id') & first['data'].pluck('id')).to be_empty
    expect(response.parsed_body['next_cursor']).to be_nil
  end

  it 'limits an assigned operator to functional events and immediately honors revoked membership' do
    member = create(:inbox_member, inbox: inbox, user: agent)
    JrcBrokerConnectionEvent.create!(account: account, inbox: inbox, user: admin, event_type: 'SESSION_FAILED', occurred_at: Time.current,
                                    metadata: { result: 'FAILED', error_code: 'PROVIDER_UNAVAILABLE', source_ip: '192.0.2.10' })
    get url, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['data'].first['metadata']).to eq('result' => 'FAILED')
    member.destroy!
    get url, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects unsafe filters and foreign inboxes' do
    get url, headers: admin.create_new_auth_token, params: { before: '1 OR 1=1' }
    expect(response).to have_http_status(:bad_request)
    get url, headers: admin.create_new_auth_token, params: { event_type: 'unknown' }
    expect(response).to have_http_status(:bad_request)
    get url.sub("/inboxes/#{inbox.id}/", "/inboxes/#{create(:channel_api).inbox.id}/"), headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'renames the same connection atomically and audits old and new names without resetting its policy' do
    before_name = inbox.name
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin,
                                                 enabled: false, mode: 'priority', team_ids: [], max_open: 4)
    original = JrcHumanAssignment::Policy.connection_for(account.reload, inbox.id)
    config_url = url.sub('/history', '/configuration')
    patch config_url, headers: admin.create_new_auth_token, params: { name: 'Commercial WhatsApp' }, as: :json
    expect(response).to have_http_status(:ok)
    expect(inbox.reload.name).to eq('Commercial WhatsApp')
    expect(JrcHumanAssignment::Policy.connection_for(account.reload, inbox.id)).to eq(original)
    expect(JrcBrokerConnectionEvent.where(account: account).last.metadata).to include('previous_name' => before_name,
                                                                                   'next_name' => 'Commercial WhatsApp')
    patch config_url, headers: agent.create_new_auth_token, params: { name: 'Denied' }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(inbox.reload.name).to eq('Commercial WhatsApp')
  end
end

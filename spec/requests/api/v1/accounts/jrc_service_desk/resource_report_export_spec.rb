# frozen_string_literal: true

require 'rails_helper'
require 'csv'

RSpec.describe 'Asset inventory summaries and CSV export', type: :request do
  include_context 'JRC Service Desk domain'
  let(:path) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/resources" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:asset) do
    JrcServiceDesk::OperationalResourceService.new(user_context: sd_context).create(
      unit_id: sd_unit.id,
      attributes: {
        resource_kind: 'asset', priority: 'normal', name: '=Synthetic monitor', code: 'TEST-MONITOR',
        details: { serial: 'SERIAL-EXACT-19', manufacturer: 'Synthetic', location: 'Matriz' }
      },
      idempotency_key: 'asset-export-fixture'
    )
  end
  before { sd_as_admin! }

  it 'returns real filtered state counts and searches serial numbers in the inventory' do
    asset
    get path, params: { unit_id: sd_unit.id, resource_kind: 'asset', query: 'SERIAL-EXACT-19' }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['summary']).to eq('total' => 1, 'by_state' => { 'active' => 1 })
    expect(response.parsed_body['items'].pluck('id')).to eq([asset.id.to_s])
    get path, params: { unit_id: sd_unit.id, resource_kind: 'asset', query: 'missing-serial' }, headers: headers
    expect(response.parsed_body['summary']).to eq('total' => 0, 'by_state' => {})
  end

  it 'exports the filtered authorized inventory and audits the export on its unit' do
    asset
    expect do
      get "#{path}/export", params: { unit_id: sd_unit.id, resource_kind: 'asset', query: 'SERIAL-EXACT-19' }, headers: headers
    end.to change { Audited::Audit.where(auditable: sd_unit, action: 'export').count }.by(1)
    expect(response).to have_http_status(:ok), response.body
    expect(response.media_type).to eq('text/csv')
    expect(response.body).to include("'=Synthetic monitor", 'SERIAL-EXACT-19')
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'does not grant inventory access to common agents or a foreign account' do
    asset
    sd_account_user.update!(role: :agent)
    get "#{path}/export", params: { unit_id: sd_unit.id, resource_kind: 'asset' }, headers: headers
    expect(response).to have_http_status(:forbidden)
    get "/api/v1/accounts/#{sd_foreign_account.id}/jrc_service_desk/resources/export", params: { unit_id: sd_unit.id }, headers: headers
    expect(response.status).to be_in([401, 403, 404])
  end
end

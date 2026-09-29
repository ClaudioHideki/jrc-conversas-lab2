# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'CP6 catalogue API', type: :request do
  include_context 'JRC Service Desk domain'
  before { sd_as_admin! }
  let(:root) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/configuration" }
  let(:headers) { sd_user.create_new_auth_token }
  def body; JSON.parse(response.body); end
  def request_headers(key); headers.merge('Idempotency-Key' => key); end

  %w[queues categories priorities statuses services].each do |resource|
    it "creates, reads, deactivates and reads #{resource} with audit proof and true pagination" do
      fields = { name: 'CP6 catalogue', code: 'cp6', active: true }
      fields[:team_id] = nil if resource == 'queues'
      fields[:position] = 0 if %w[priorities statuses].include?(resource)
      fields.merge!(phase: 'open', initial: true) if resource == 'statuses'
      post "#{root}/#{resource}", params: { unit_id: sd_unit.id, record: fields }, headers: request_headers(SecureRandom.uuid), as: :json
      expect(response).to have_http_status(:created)
      id = body['record']['id']; audit_id = body['audit_id']; revision = body['record']['revision']
      get "#{root}/#{resource}/#{id}/receipts/#{audit_id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(body['receipt']['after']['active']).to be(true)
      expect(body['receipt']['author_account_user_id']).to eq(sd_account_user.id.to_s)
      get "#{root}/#{resource}/#{id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(body['record']['name']).to eq('CP6 catalogue')
      patch "#{root}/#{resource}/#{id}", params: { record: { active: false }, expected_revision: revision }, headers: request_headers(SecureRandom.uuid), as: :json
      expect(response).to have_http_status(:ok)
      get "#{root}/#{resource}", params: { unit_id: sd_unit.id, page: 1, per_page: 20, active: 'false' }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(body['meta']['total']).to eq(1)
      expect(body['items'].first['active']).to be(false)
      get "#{root}/#{resource}", params: { unit_id: sd_unit.id, active: 'true' }, headers: headers
      expect(body['items']).to eq([])
      expect(body['meta']['total']).to eq(0)
      expect(response.headers['Cache-Control']).to include('no-store')
    end
  end

  it 'denies feature-off and unauthorized agent but allows admin configuration without membership' do
    params = { unit_id: sd_unit.id }
    sd_account.disable_features!('jrc_service_desk')
    get "#{root}/categories", params: params, headers: headers
    expect(response).to have_http_status(:forbidden)
    sd_account.enable_features!('jrc_service_desk'); sd_account_user.update!(role: :agent)
    get "#{root}/categories", params: params, headers: headers
    expect(response).to have_http_status(:forbidden)
    sd_as_admin!; sd_membership.update!(active: false)
    get "#{root}/categories", params: params, headers: headers
    expect(response).to have_http_status(:ok)
    expect(sd_membership.reload.active).to be(false)
  end

  it 'rejects foreign records/units, injected fields and malformed pagination' do
    row = create(:jrc_sd_category, unit: sd_foreign_unit)
    get "#{root}/categories/#{row.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    get "#{root}/categories", params: { unit_id: sd_foreign_unit.id }, headers: headers
    expect(response).to have_http_status(:not_found)
    post "#{root}/categories", params: { unit_id: sd_unit.id, record: { name: 'bad', code: 'bad', active: true, account_id: sd_foreign_account.id } }, headers: request_headers(SecureRandom.uuid), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    get "#{root}/categories", params: { unit_id: sd_unit.id, page: '01' }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'lists inactive catalogues only through management, not operational lookups' do
    row = create(:jrc_sd_category, unit: sd_unit, active: false)
    get "#{root}/categories", params: { unit_id: sd_unit.id }, headers: headers
    expect(body['items'].map { |x| x['id'] }).to include(row.id.to_s)
    get "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/categories", params: { unit_id: sd_unit.id }, headers: headers
    expect(body['items']).to eq([])
  end
end

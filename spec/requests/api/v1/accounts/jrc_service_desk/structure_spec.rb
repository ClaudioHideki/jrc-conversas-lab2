# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'CP6-D01 native client structural API', type: :request do
  include_context 'JRC Service Desk domain'
  let(:headers) { sd_user.create_new_auth_token }
  let(:root) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/structure" }
  let(:role) { create(:custom_role, account: sd_account, permissions: %w[structure_view operator_companies_manage units_manage unit_memberships_manage].map { |k| "jrc_service_desk_#{k}" }) }
  before do
    skip 'Native CustomRole unavailable - pending' unless defined?(CustomRole)
    sd_account_user.update!(role: :administrator, custom_role: role)
  end
  def body; JSON.parse(response.body); end

  it 'uses native identity and separate structural capabilities without exposing tickets' do
    sd_membership.update!(active: false)
    get "#{root}/context", headers: headers
    expect(response).to have_http_status(:ok)
    expect(body['account_user_id']).to eq(sd_account_user.id.to_s)
    expect(body).not_to have_key('tickets')
    get "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/tickets", headers: headers
    expect(response).to have_http_status(:forbidden)
    get "#{root}/units", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'writes, audits, reads back and deactivates with real records' do
    post "#{root}/units", headers: headers.merge('Idempotency-Key' => 'unit-created'), params: {
      record: { name: 'D01 unit', code: 'd01-unit', active: true, operator_company_id: sd_operator.id }, reason: 'CHG-1' }, as: :json
    expect(response).to have_http_status(:created)
    id, audit_id, revision = body['record']['id'], body['audit_id'], body['record']['revision']
    get "#{root}/units/#{id}/receipts/#{audit_id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(body['receipt']['after']['name']).to eq('D01 unit')
    get "#{root}/units/#{id}", headers: headers
    expect(body['record']['name']).to eq('D01 unit')
    patch "#{root}/units/#{id}", headers: headers.merge('Idempotency-Key' => 'unit-deactivated'), params: {
      record: { active: false }, expected_revision: revision, reason: 'CHG-2' }, as: :json
    expect(response).to have_http_status(:ok)
    expect(JrcServiceDesk::Unit.find(id).active?).to be(false)
    expect(JrcServiceDesk::UnitMembership.where(unit_id: id)).to be_empty
  end

  it 'rejects foreign records, forged body ownership, missing capabilities and flag false' do
    get "#{root}/units/#{sd_foreign_unit.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    post "#{root}/operator_companies", headers: headers.merge('Idempotency-Key' => 'bad'), params: {
      record: { name: 'X', code: 'x', active: true, account_id: sd_foreign_account.id }, reason: 'CHG-2' }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    role.update!(permissions: [])
    get "#{root}/context", headers: headers
    expect(response).to have_http_status(:forbidden)
    sd_account.disable_features!('jrc_service_desk')
    get "#{root}/units", headers: headers
    expect(response).to have_http_status(:forbidden)
  end
end

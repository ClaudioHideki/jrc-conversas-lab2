# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk unit access administration', type: :request do
  include_context 'JRC Service Desk domain'

  let(:headers) { sd_user.create_new_auth_token }
  let(:root) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/structure" }
  let(:permissions) { %w[jrc_service_desk_structure_view jrc_service_desk_unit_memberships_manage] }
  let(:role) { create(:custom_role, account: sd_account, permissions: permissions) }
  let(:recipient) { create(:account_user, account: sd_account, role: :agent) }
  let(:foreign_recipient) { create(:account_user, account: sd_foreign_account) }

  before do
    sd_account_user.update!(role: :administrator, custom_role: role)
    sd_membership.update!(active: false)
    recipient.user.confirm
  end

  def payload
    response.parsed_body
  end

  def directory
    get "#{root}/members", params: { unit_id: sd_unit.id, q: recipient.user.name }, headers: headers
    expect(response).to have_http_status(:ok)
    payload['items'].find { |item| item['id'] == recipient.id.to_s }
  end

  def write_membership(active, existing = nil)
    args = membership_attributes(active, existing)
    if existing
      patch "#{root}/unit_memberships/#{existing.fetch('id')}", params: args, as: :json,
                                                                headers: headers.merge('Idempotency-Key' => SecureRandom.uuid)
      expect(response).to have_http_status(:ok)
    else
      post "#{root}/unit_memberships", params: args, as: :json,
                                       headers: headers.merge('Idempotency-Key' => SecureRandom.uuid)
      expect(response).to have_http_status(:created)
    end
    payload
  end

  def membership_attributes(active, existing)
    args = { record: { active: active }, reason: active ? 'Approved unit access' : 'Revoked unit access' }
    if existing
      args[:expected_revision] = existing.fetch('revision')
    else
      args[:record].merge!(unit_id: sd_unit.id, account_user_id: recipient.id)
    end
    args
  end

  it 'creates, rereads, revokes and reactivates the same membership with persisted audit receipts' do
    expect(directory['membership']).to be_nil
    created = write_membership(true)
    record = created.fetch('record')
    expect(directory['membership']).to eq(record)
    [false, true].each do |active|
      result = write_membership(active, record)
      record = result.fetch('record')
      get "#{root}/unit_memberships/#{record['id']}/receipts/#{result['audit_id']}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(payload['receipt']['before']['active']).to eq(!active)
      expect(payload['receipt']['after']['active']).to eq(active)
      expect(directory['membership']['active']).to eq(active)
    end
    expect(JrcServiceDesk::UnitMembership.where(account_user: recipient, unit: sd_unit).count).to eq(1)
  end

  it 'audits a new grant without granting operational access to the administrator' do
    created = write_membership(true)
    get "#{root}/unit_memberships/#{created['record']['id']}/receipts/#{created['audit_id']}", headers: headers
    expect(payload['receipt']['before']).to be_nil
    expect(payload['receipt']['after']['active']).to be(true)
    expect(sd_membership.reload.active).to be(false)
    get "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/ui_context", headers: headers
    expect(response).to have_http_status(:forbidden)
  end

  it 'projects current role, effective capabilities, company and unit without granting scope' do
    row = directory
    expect(row['role']).to eq('agent')
    expect(row['capabilities']).to include('module_view')
    expect(payload['operator_company']['id']).to eq(sd_operator.id.to_s)
    expect(payload['unit']['id']).to eq(sd_unit.id.to_s)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(row['membership']).to be_nil
  end

  it 'rejects foreign account and unit reads' do
    get "#{root}/members", params: { unit_id: sd_foreign_unit.id }, headers: headers
    expect(response).to have_http_status(:not_found)
    get "/api/v1/accounts/#{sd_foreign_account.id}/jrc_service_desk/structure/members", headers: headers
    expect(response.status).to be_in([401, 403, 404])
  end

  it 'rejects foreign units and recipients on writes without creating a membership' do
    [[sd_foreign_unit.id, recipient.id], [sd_unit.id, foreign_recipient.id]].each do |unit_id, account_user_id|
      expect do
        post "#{root}/unit_memberships", params: {
          record: { unit_id: unit_id, account_user_id: account_user_id, active: true }, reason: 'Rejected foreign grant'
        }, as: :json, headers: headers.merge('Idempotency-Key' => SecureRandom.uuid)
      end.not_to change(JrcServiceDesk::UnitMembership, :count)
      expect(response.status).to be_in([403, 404, 422])
    end
  end

  it 'denies native administrators without the explicit structural capability' do
    sd_account_user.update!(custom_role: nil)
    get "#{root}/members", params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:forbidden)
  end

  it 'denies membership administration when only structure viewing is delegated' do
    role.update!(permissions: ['jrc_service_desk_structure_view'])
    get "#{root}/members", params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:forbidden)
  end

  it 'denies administration when the feature is off' do
    sd_account.disable_features!('jrc_service_desk')
    get "#{root}/members", params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:forbidden)
  end

  it 'requires both scope and action capability; team membership grants neither' do
    recipient_headers = recipient.user.create_new_auth_token
    endpoint = "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/ui_context"
    create(:team_member, team: create(:team, account: sd_account), user: recipient.user)
    get endpoint, headers: recipient_headers
    expect(response).to have_http_status(:forbidden)
    operational_role = create(:custom_role, account: sd_account, permissions: [])
    recipient.update!(custom_role: operational_role)
    write_membership(true)
    get endpoint, headers: recipient_headers
    expect(response).to have_http_status(:forbidden)
    operational_role.update!(permissions: %w[jrc_service_desk_module_view jrc_service_desk_tickets_view])
    get endpoint, headers: recipient_headers
    expect(response).to have_http_status(:ok)
    expect(directory['capabilities']).to include('module_view', 'tickets_view')
  end
end

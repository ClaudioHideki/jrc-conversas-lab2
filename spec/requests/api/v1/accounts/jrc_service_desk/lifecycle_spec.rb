# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'CP4-D01 lifecycle HTTP persistence and readback', type: :request do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token }
  def json
    JSON.parse(response.body)
  end

  it 'publishes an explicit version, reads it independently and creates a scoped service identity' do
    sd_as_admin!
    post "#{base}/service_definitions", headers: headers, as: :json,
      params: { unit_id: sd_unit.id, service: { name: 'HTTP service fixture', code: 'http-fixture', active: true } }
    expect(response).to have_http_status(:created)
    service_id = json.fetch('service').fetch('id')
    get "#{base}/service_definitions/#{service_id}", headers: headers
    expect(json.dig('service', 'unit_id')).to eq(sd_unit.id.to_s)
    post "#{base}/lifecycle_policies", headers: headers, as: :json,
      params: { unit_id: sd_unit.id, policy: { name: 'Policy fixture', service_id: service_id, enabled: true, expected_version: 0, definition: lc_definition } }
    expect(response).to have_http_status(:created)
    policy_id = json.fetch('policy').fetch('id')
    get "#{base}/lifecycle_policies/#{policy_id}", headers: headers
    expect(json.dig('policy', 'version')).to eq(1)
    expect(json.dig('policy', 'service_id')).to eq(service_id)
    get "#{base}/lifecycle_policies", headers: headers, params: { unit_id: sd_unit.id }
    expect(json.dig('meta', 'total')).to eq(1)
  end

  it 'executes all six business flows through POST and independent ticket/history/dashboard GETs' do
    definition = lc_definition; definition['reopen']['anchor_action'] = 'cancel'
    lc_publish(definition: definition)
    row = sd_ticket
    %w[pause resume resolve cancel reopen resolve close].each_with_index do |key, index|
      get "#{base}/tickets/#{row.id}/lifecycle", headers: headers
      expect(response).to have_http_status(:ok)
      selected = json['options'].find { |option| option['key'] == key }
      expect(selected).to be_present
      attributes = { rule_key: key, expected_lock_version: json['lock_version'], expected_policy_version_id: json.dig('policy', 'id') }
      attributes[:reason_code] = 'customer' if key == 'pause'
      post "#{base}/tickets/#{row.id}/lifecycle", headers: headers.merge('Idempotency-Key' => "flow-#{index}"), as: :json, params: attributes
      expect(response).to have_http_status(:ok)
      transition_id = json.fetch('result_id')
      get "#{base}/tickets/#{row.id}/lifecycle/transitions/#{transition_id}", headers: headers
      expect(json.dig('transition', 'action')).to eq(key)
      get "#{base}/tickets/#{row.id}", headers: headers
      expect(json.dig('ticket', 'status', 'id')).to eq(selected['to_status_id'])
      get "#{base}/tickets/#{row.id}/lifecycle", headers: headers
      expect(json.dig('meta', 'total')).to eq(index + 1)
      get "#{base}/dashboard", headers: headers
      kpi = json.fetch('dashboard')
      expect(kpi['total']).to eq(kpi['phases'].values.sum)
      expect(kpi['active']).to eq(kpi['phases']['open'] + kpi['phases']['waiting'])
    end
    expect(row.reload.status.phase).to eq('closed')
  end

  it 'denies missing policy, forged body IDs, stale policy selection, account/unit mismatch and revoked grants' do
    row = sd_ticket
    post "#{base}/tickets/#{row.id}/lifecycle", headers: headers.merge('Idempotency-Key' => 'no-policy'), as: :json, params: { rule_key: 'resolve', expected_lock_version: 0, expected_policy_version_id: 1 }
    expect(response).to have_http_status(:forbidden)
    policy = lc_publish
    attributes = { rule_key: 'resolve', expected_lock_version: row.lock_version, expected_policy_version_id: policy.current_version_id }
    post "#{base}/tickets/#{row.id}/lifecycle", headers: headers.merge('Idempotency-Key' => 'forged'), as: :json, params: attributes.merge(account_id: sd_foreign_account.id)
    expect(response).to have_http_status(:unprocessable_entity)
    post "#{base}/tickets/#{row.id}/lifecycle", headers: headers.merge('Idempotency-Key' => 'stale-policy'), as: :json, params: attributes.merge(expected_policy_version_id: policy.current_version_id + 999)
    expect(response).to have_http_status(:conflict)
    foreign = create(:jrc_sd_ticket, unit: sd_foreign_unit)
    get "#{base}/tickets/#{foreign.id}/lifecycle", headers: headers
    expect(response).to have_http_status(:not_found)
    sd_as_admin!
    get "#{base}/lifecycle_policies", headers: headers, params: { unit_id: sd_other_unit.id }
    expect([403, 404]).to include(response.status)
    sd_membership.update!(active: false)
    get "#{base}/tickets/#{row.id}/lifecycle", headers: headers
    expect([403, 404]).to include(response.status)
    sd_membership.update!(active: true)
    sd_account.disable_features!('jrc_service_desk')
    get "#{base}/tickets/#{row.id}/lifecycle", headers: headers
    expect(response).to have_http_status(:forbidden)
    expect(row.reload.status.phase).to eq('open')
  end

  it 'returns an explicit dependency error instead of a fake transition if calendar data is absent' do
    policy = lc_publish(definition: lc_definition(tracked: true)); row = sd_ticket
    post "#{base}/tickets/#{row.id}/lifecycle", headers: headers.merge('Idempotency-Key' => 'missing-calendar'), as: :json,
      params: { rule_key: 'resolve', expected_lock_version: row.lock_version, expected_policy_version_id: policy.current_version_id }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(json['code']).to eq('lifecycle_dependency')
    expect(row.reload.status.phase).to eq('open')
    expect(row.lifecycle_transitions.count).to eq(0)
  end
end

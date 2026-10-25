# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Coordinated Service Desk publications', type: :request do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  let(:root) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/automation_publications" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:queue) { create(:jrc_sd_queue, unit: sd_unit) }
  let(:attributes) do
    { kind: 'operational', code: 'http-test', name: 'HTTP synthetic policy', description: '', service_id: nil, enabled: false,
      definition: { lifecycle: nil, queues: [], notifications: [], families: { routing: { rules: [
        { key: 'route', precedence: 7, match: { priority_id: sd_priority.id }, output: { queue_id: queue.id } }
      ] } } } }
  end
  let(:command) do
    preview = JrcServiceDesk::AutomationPublicationService.new(user_context: sd_context).preview(unit_id: sd_unit.id, attributes: attributes.deep_stringify_keys)
    { unit_id: sd_unit.id, attributes: attributes, expected_version: 0, expected_native_versions: preview[:native_versions], confirmed: true, idempotency_key: 'http-publication' }
  end
  before { sd_as_admin! }

  it 'authorizes the real preview action and returns a side-effect-free simulation over HTTP' do
    input = { unit_id: sd_unit.id, attributes: attributes, facts: {} }
    counts = [JrcServiceDesk::AutomationPublication.count, JrcServiceDesk::OperationalRuleVersion.count, Audited::Audit.count, Message.count]
    post "#{root}/preview", headers: headers, as: :json, params: input
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('preview', 'valid')).to be(true)
    expect(response.parsed_body.dig('preview', 'effects').values).to all(be(false))
    expect([JrcServiceDesk::AutomationPublication.count, JrcServiceDesk::OperationalRuleVersion.count, Audited::Audit.count, Message.count]).to eq(counts)
    sd_account_user.update!(role: :agent)
    post "#{root}/preview", headers: headers, as: :json, params: input
    expect(response).to have_http_status(:forbidden)
    expect(JrcServiceDesk::AutomationPublication.count).to eq(0)
  end

  it 'returns real SLA calendar deadlines over HTTP without publishing or starting a clock' do
    calendar = { format: 'jrc-sd-snapshot-calendar-v1', weekly: (1..7).to_h { |day| [day.to_s, day <= 5 ? [['09:00', '17:00']] : []] }, holidays: [], exceptions: {} }
    snapshot = sd_snapshot_attributes.except(:captured_at).merge(calendar_conditions: calendar,
      policy_conditions: { clock_budgets_seconds: { first_response: 300, resolution: 7200 } })
    input = attributes.deep_dup
    input[:kind] = 'lifecycle'
    input[:definition][:lifecycle] = lc_definition(tracked: true)
    input[:definition][:families] = { sla_selection: { rules: [{ key: 'calendar-proof', precedence: 1,
      match: { priority_id: sd_priority.id }, output: { snapshot: snapshot } }] } }
    post "#{root}/preview", headers: headers, as: :json,
      params: { unit_id: sd_unit.id, attributes: input, facts: {}, at: '2026-10-25T12:00:00Z' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('preview', 'sla_deadlines', 0, 'due_at')).to eq(
      'first_response' => '2026-10-26T12:05:00Z', 'resolution' => '2026-10-26T14:00:00Z')
    expect(JrcServiceDesk::AutomationPublication.count).to eq(0)
    expect(JrcServiceDesk::SlaClock.count).to eq(0)
  end

  it 'publishes over authenticated HTTP, then independently reads the receipt and native version' do
    post root, headers: headers, as: :json, params: command
    expect(response).to have_http_status(:created)
    payload = response.parsed_body
    expect(payload['publication']['enabled']).to be(false)
    expect(payload['audit_id']).to be_present
    get "#{root}/#{payload['publication']['id']}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['publication']).to eq(payload['publication'])
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'returns real latest-version metrics, filters and scoped choices' do
    JrcServiceDesk::AutomationPublicationService.new(user_context: sd_context).call(**command)
    get root, headers: headers, params: { unit_id: sd_unit.id, kind: 'operational', q: 'http-test', active: 'false', page: 1 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['total']).to eq(1)
    expect(response.parsed_body['counts']).to eq('total' => 1, 'enabled' => 0, 'disabled' => 1)
    own_label = create(:label, account: sd_account)
    foreign_label = create(:label, account: sd_foreign_account)
    get "#{root}/options", headers: headers, params: { unit_id: sd_unit.id, kind: 'operational' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['labels'].pluck('id')).to include(own_label.id)
    expect(response.parsed_body['labels'].pluck('id')).not_to include(foreign_label.id)
  end

  it 'rejects unauthenticated requests without writes' do
    input = command
    expect { post root, as: :json, params: input }.not_to change(JrcServiceDesk::AutomationPublication, :count)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects a native agent without management permissions without writes' do
    input = command
    sd_account_user.update!(role: :agent)
    expect { post root, headers: headers, as: :json, params: input }.not_to change(JrcServiceDesk::OperationalRuleVersion, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it 'does not leak or publish another Account or unauthorized unit' do
    input = command
    post root, headers: headers, as: :json, params: input.merge(unit_id: sd_foreign_unit.id)
    expect(response).to have_http_status(:not_found)
    sd_account_user.update!(role: :agent)
    get root, headers: headers, params: { unit_id: sd_other_unit.id, kind: 'operational' }
    expect(response).to have_http_status(:forbidden)
    expect(JrcServiceDesk::AutomationPublication.count).to eq(0)
  end

  it 'rejects unknown controls and credential-shaped payloads' do
    input = command
    post root, headers: headers, as: :json, params: input.merge(attributes: attributes.merge(password: 'synthetic-forbidden-value'))
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).not_to include('synthetic-forbidden-value')
    expect(JrcServiceDesk::AutomationPublication.count).to eq(0)
  end

  it 'does not activate anything when saving a private draft and protects it from another administrator' do
    put root.sub('automation_publications', 'automation_drafts'), headers: headers, as: :json,
      params: { unit_id: sd_unit.id, kind: 'operational', code: 'private', payload: { attributes: attributes }, expected_version: -1 }
    expect(response).to have_http_status(:ok)
    expect(JrcServiceDesk::OperationalRuleVersion.count).to eq(0)
    another = create(:user)
    create(:account_user, account: sd_account, user: another, role: :administrator)
    get root.sub('automation_publications', 'automation_drafts'), headers: another.create_new_auth_token,
      params: { unit_id: sd_unit.id, kind: 'operational', code: 'private' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['draft']).to be_nil
  end

  it 'requires explicit confirmation and native expected versions' do
    input = command
    post root, headers: headers, as: :json, params: input.merge(confirmed: false)
    expect(response).to have_http_status(:unprocessable_entity)
    post root, headers: headers, as: :json, params: input.merge(expected_native_versions: {})
    expect(response).to have_http_status(:conflict)
    expect(JrcServiceDesk::AutomationPublication.count).to eq(0)
  end
end

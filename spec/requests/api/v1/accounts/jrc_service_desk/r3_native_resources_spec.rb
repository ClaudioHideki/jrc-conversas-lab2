# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk R3 native resources and problems', type: :request do
  include_context 'JRC Service Desk domain'
  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:ticket) { sd_ticket }
  let(:asset) do
    { resource_kind: 'asset', name: 'Router LAB', code: 'LAB-01', priority: 'normal',
      details: { serial: 'SERIAL-LOCAL' }, ticket_ids: [ticket.id.to_s] }
  end
  let(:manager_role) do
    create(:custom_role, account: sd_account,
                         permissions: JrcServiceDesk::Capabilities::DEFAULTS.fetch('administrator').map { |key| "jrc_service_desk_#{key}" })
  end

  before { sd_account_user.update!(role: :administrator, custom_role: manager_role) }

  def resource_post(values, key = 'resource-local')
    post "#{base}/resources", params: { unit_id: sd_unit.id, resource: values },
                              headers: headers.merge('Idempotency-Key' => key), as: :json
  end

  it 'creates an asset, reuses the same request safely and reads authoritative ticket links without caching' do
    resource_post(asset)
    expect(response).to have_http_status(:created)
    id = response.parsed_body.dig('resource', 'id')
    resource_post(asset)
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig('resource', 'id')).to eq(id)
    expect(JrcServiceDesk::OperationalResource.count).to eq(1)
    get "#{base}/resources/#{id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('resource', 'ticket_ids')).to eq([ticket.id.to_s])
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'archives a native asset while retaining history, ticket links and notification OFF' do
    resource_post(asset)
    expect(response).to have_http_status(:created)
    id = response.parsed_body.dig('resource', 'id')
    delete "#{base}/resources/#{id}", params: { unit_id: sd_unit.id, expected_lock_version: 0 }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    get "#{base}/resources/#{id}", headers: headers
    expect(response.parsed_body.dig('resource', 'state')).to eq('retired')
    expect(response.parsed_body.dig('resource', 'history').pluck('action')).to eq(%w[created archived])
    expect(ticket.reload.ticket_events.pluck(:event_type)).to include('resource_linked', 'resource_archived')
    expect(JrcServiceDesk::NotificationDelivery.count).to eq(0)
  end

  it 'rejects a changed payload using the same key and a stale update without changing the native record' do
    resource_post(asset)
    expect(response).to have_http_status(:created)
    id = response.parsed_body.dig('resource', 'id')
    resource_post(asset.merge(name: 'Different router'))
    expect(response).to have_http_status(:conflict)
    patch "#{base}/resources/#{id}", params: { unit_id: sd_unit.id, resource: { state: 'inactive' }, expected_lock_version: 9 },
                                     headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(JrcServiceDesk::OperationalResource.find(id).state).to eq('active')
  end

  it 'rejects an inaccessible unit link and rolls back the whole create' do
    other_member = create(:account_user, account: sd_account, role: :agent)
    foreign = sd_ticket(unit: sd_other_unit, status: create(:jrc_sd_status, unit: sd_other_unit),
                        priority: create(:jrc_sd_priority, unit: sd_other_unit),
                        created_by_membership: create(:jrc_sd_membership, unit: sd_other_unit, account_user: other_member))
    resource_post(asset.merge(ticket_ids: [foreign.id]))
    expect(response).to have_http_status(:not_found)
    expect(JrcServiceDesk::OperationalResource.count).to eq(0)
    expect(JrcServiceDesk::ResourceTicketLink.count).to eq(0)
  end

  it 'revokes resource read and mutation when the current unit grant is removed' do
    resource_post(asset)
    expect(response).to have_http_status(:created)
    id = response.parsed_body.dig('resource', 'id')
    sd_membership.update!(active: false)
    get "#{base}/resources/#{id}", headers: headers
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body['code']).to eq('forbidden')
    patch "#{base}/resources/#{id}", params: { unit_id: sd_unit.id, resource: { state: 'inactive' }, expected_lock_version: 0 },
                                     headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body['code']).to eq('forbidden')
    expect(JrcServiceDesk::OperationalResource.find(id).state).to eq('active')
  end

  it 'requires an explicit planned window and an approved native approval before a change may advance' do
    resource_post({ resource_kind: 'change', name: 'Local planned switch', priority: 'normal', ticket_ids: [ticket.id] })
    expect(response).to have_http_status(:created)
    id = response.parsed_body.dig('resource', 'id')
    patch "#{base}/resources/#{id}", params: { unit_id: sd_unit.id, resource: { state: 'planned' }, expected_lock_version: 0 },
                                     headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    planned = { state: 'planned', planned_start_at: '2026-10-12T13:00:00Z', planned_end_at: '2026-10-12T14:00:00Z' }
    patch "#{base}/resources/#{id}", params: { unit_id: sd_unit.id, resource: planned, expected_lock_version: 0 }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    approval = JrcServiceDesk::CreateApprovalService.new(user_context: sd_context).call(
      ticket_id: ticket.id, attributes: { title: 'Approve planned change', approver_account_user_id: sd_account_user.id,
                                          due_at: '2026-10-11T12:00:00Z' }, idempotency_key: 'change-approval'
    )
    values = { state: 'approved', approval_id: approval.id }
    patch "#{base}/resources/#{id}", params: { unit_id: sd_unit.id, resource: values, expected_lock_version: 1 }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    JrcServiceDesk::DecideApprovalService.new(user_context: sd_context).call(ticket_id: ticket.id, approval_id: approval.id,
                                                                             attributes: { status: 'approved' }, expected_lock_version: 0)
    patch "#{base}/resources/#{id}", params: { unit_id: sd_unit.id, resource: values, expected_lock_version: 1 }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    get "#{base}/resources/#{id}", headers: headers
    expect(response.parsed_body.dig('resource', 'state')).to eq('approved')
  end

  it 'creates a native problem with cause/workaround, keeps incidents separate and reads the authoritative update' do
    post "#{base}/incidents", params: { unit_id: sd_unit.id, incident: { title: 'Recurring local fault', severity: 'high', resource_kind: 'problem',
                                                                         owner_account_user_id: sd_account_user.id, ticket_ids: [ticket.id] } },
                            headers: headers.merge('Idempotency-Key' => 'problem-local'), as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.dig('incident', 'id')
    update = { status: 'investigating', cause: 'Intermittent cable', workaround: 'Local bypass' }
    patch "#{base}/incidents/#{id}", params: { unit_id: sd_unit.id, incident: update, expected_lock_version: 0 }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    get "#{base}/incidents/#{id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('incident', 'cause')).to eq('Intermittent cable')
    get "#{base}/board", params: { kind: 'problems', unit_id: sd_unit.id, status: 'investigating', query: 'Recurring' }, headers: headers
    expect(response.parsed_body['items'].pluck('id')).to eq([id])
    get "#{base}/board", params: { kind: 'incidents', unit_id: sd_unit.id }, headers: headers
    expect(response.parsed_body['items']).to eq([])
    expect(ticket.reload.incident_id).to eq(id.to_i)
  end
end

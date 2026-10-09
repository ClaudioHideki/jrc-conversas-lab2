# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk historical SLA snapshot HTTP wrapper', type: :request do
  include_context 'JRC Service Desk domain'

  let(:ticket) { sd_ticket }
  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/tickets/#{ticket.id}" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:read_keys) { %w[module_view tickets_view sla_view contract_conditions_view] }
  let(:role) { create(:custom_role, account: sd_account, permissions: read_keys.map { |key| "jrc_service_desk_#{key}" }) }

  before { sd_as_admin! }

  it 'records the native conditions, provenance, pending milestones and real actor, then reads the persisted snapshot' do
    expect do
      post "#{base}/sla_snapshots", headers: headers, as: :json, params: { snapshot: sd_snapshot_attributes }
    end.to change(JrcServiceDesk::SlaSnapshot, :count).by(1)
    expect(response).to have_http_status(:ok)
    result = response.parsed_body
    snapshot = ticket.sla_snapshots.sole
    expect(result.slice('contract_version', 'account_id', 'unit_id', 'ticket_id', 'applied')).to eq(
      'contract_version' => 1, 'account_id' => sd_account.id.to_s, 'unit_id' => sd_unit.id.to_s,
      'ticket_id' => ticket.id.to_s, 'applied' => true)
    expect(result.dig('snapshot', 'id')).to eq(snapshot.id.to_s)
    expect(result.dig('snapshot', 'payload_digest')).to eq(snapshot.expected_digest)
    expect(result.dig('snapshot', 'source')).to eq('system' => 'test-provider', 'reference' => 'test-contract', 'version' => 'v1')
    expect(result.dig('snapshot', 'policy')).to eq('key' => 'test-policy', 'version' => 'v1')
    expect(result.dig('snapshot', 'calendar')).to eq('key' => 'test-calendar', 'version' => 'v1', 'scope' => 'unit')
    expect(result.dig('snapshot', 'conditions')).to eq(
      'contract' => snapshot.contract_conditions, 'policy' => snapshot.policy_conditions, 'calendar' => snapshot.calendar_conditions)
    expect(result.dig('snapshot', 'timezone')).to eq(snapshot.timezone)
    expect(result.dig('snapshot', 'captured_at')).to eq(snapshot.captured_at.iso8601(6))
    expect(result.dig('snapshot', 'applied_at')).to eq(snapshot.applied_at.iso8601(6))
    expect(snapshot.sla_milestones.pluck(:kind)).to match_array(%w[first_response resolution])
    expect(snapshot.sla_milestones.pluck(:due_at, :achieved_at)).to eq([[nil, nil], [nil, nil]])
    expect(JrcServiceDesk::SlaClock.where(ticket_id: ticket.id).count).to eq(0)
    event = ticket.ticket_events.sole
    expect(event.event_type).to eq('sla_snapshot_recorded')
    expect(event.actor_membership_id).to eq(sd_membership.id)
    get "#{base}/sla_snapshots/#{snapshot.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('snapshot')).to eq(result.fetch('snapshot'))
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'replays equivalent native evidence without another snapshot, milestone or audit event' do
    post "#{base}/sla_snapshots", headers: headers, as: :json, params: { snapshot: sd_snapshot_attributes }
    original = response.parsed_body.fetch('snapshot')
    count = ticket.ticket_events.count
    post "#{base}/sla_snapshots", headers: headers, as: :json,
      params: { snapshot: sd_snapshot_attributes.merge(captured_at: '2026-09-25T07:00:00-03:00') }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('snapshot')).to eq(original)
    expect(ticket.sla_snapshots.count).to eq(1)
    expect(ticket.sla_milestones.count).to eq(2)
    expect(ticket.ticket_events.count).to eq(count)
  end

  it 'appends new evidence without rewriting the old snapshot or editing the ticket and its clocks' do
    post "#{base}/sla_snapshots", headers: headers, as: :json, params: { snapshot: sd_snapshot_attributes }
    first = ticket.sla_snapshots.sole
    original = first.attributes.deep_dup
    ticket_version = ticket.reload.lock_version
    post "#{base}/sla_snapshots", headers: headers, as: :json,
      params: { snapshot: sd_snapshot_attributes.merge(source_version: 'v2', contract_conditions: { coverage: 'revised' }) }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('snapshot', 'version')).to eq(2)
    expect(first.reload.attributes).to eq(original)
    expect(ticket.reload.lock_version).to eq(ticket_version)
    expect(JrcServiceDesk::SlaClock.where(ticket_id: ticket.id).count).to eq(0)
    expect(ticket.sla_snapshots.count).to eq(2)
    expect(ticket.sla_milestones.count).to eq(4)
  end

  it 'does not expose raw conditions to an ordinary operator who can read operational SLA' do
    snapshot = JrcServiceDesk::RecordSlaSnapshotService.new(user_context: sd_context).call(ticket_id: ticket.id, attributes: sd_snapshot_attributes)
    sd_account_user.update!(role: :agent)
    get "#{base}/sla", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').size).to eq(2)
    expect(response.body).not_to include('contract_conditions', 'test-contract', 'calendar_conditions')
    get "#{base}/sla_snapshots/#{snapshot.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body.fetch('code')).to eq('not_found')
    expect(response.body).not_to include('test-contract', 'test-policy', 'coverage')
    expect do
      post "#{base}/sla_snapshots", headers: headers, as: :json, params: { snapshot: sd_snapshot_attributes.merge(source_version: 'v2') }
    end.not_to change(JrcServiceDesk::SlaSnapshot, :count)
    expect(response).to have_http_status(:forbidden)
    get base, headers: headers
    expect(response.parsed_body.dig('ticket', 'permissions').slice('record_sla_snapshot', 'view_contract_conditions')).to eq(
      'record_sla_snapshot' => false, 'view_contract_conditions' => false)
  end

  it 'honors a native read-only custom role and revokes recording while retaining authorized readback' do
    snapshot = JrcServiceDesk::RecordSlaSnapshotService.new(user_context: sd_context).call(ticket_id: ticket.id, attributes: sd_snapshot_attributes)
    sd_account_user.update!(custom_role: role)
    get "#{base}/sla_snapshots/#{snapshot.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('snapshot', 'permissions', 'show')).to be(true)
    expect do
      post "#{base}/sla_snapshots", headers: headers, as: :json, params: { snapshot: sd_snapshot_attributes.merge(source_version: 'v2') }
    end.not_to change(JrcServiceDesk::SlaSnapshot, :count)
    expect(response).to have_http_status(:forbidden)
    get base, headers: headers
    expect(response.parsed_body.dig('ticket', 'permissions').slice('record_sla_snapshot', 'view_contract_conditions')).to eq(
      'record_sla_snapshot' => false, 'view_contract_conditions' => true)
  end

  it 'rechecks the current raw-condition grant instead of trusting an earlier successful GET' do
    snapshot = JrcServiceDesk::RecordSlaSnapshotService.new(user_context: sd_context).call(ticket_id: ticket.id, attributes: sd_snapshot_attributes)
    sd_account_user.update!(custom_role: role)
    get "#{base}/sla_snapshots/#{snapshot.id}", headers: headers
    expect(response).to have_http_status(:ok)
    role.update!(permissions: %w[module_view tickets_view sla_view].map { |key| "jrc_service_desk_#{key}" })
    get "#{base}/sla_snapshots/#{snapshot.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(snapshot.payload_digest, 'test-contract', 'coverage')
  end

  it 'does not treat a recording grant without its native read dependencies as authority' do
    role.update!(permissions: %w[module_view tickets_view sla_snapshots_record].map { |key| "jrc_service_desk_#{key}" })
    sd_account_user.update!(custom_role: role)
    expect do
      post "#{base}/sla_snapshots", headers: headers, as: :json, params: { snapshot: sd_snapshot_attributes }
    end.not_to change(JrcServiceDesk::SlaSnapshot, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it 'redacts the command receipt if raw-condition permission is revoked after native recording' do
    native = JrcServiceDesk::RecordSlaSnapshotService.new(user_context: sd_context)
    allow(JrcServiceDesk::RecordSlaSnapshotService).to receive(:new).and_return(native)
    allow(native).to receive(:call).and_wrap_original do |method, **arguments|
      snapshot = method.call(**arguments)
      sd_account_user.update!(role: :agent)
      snapshot
    end
    post "#{base}/sla_snapshots", headers: headers, as: :json, params: { snapshot: sd_snapshot_attributes }
    expect(response).to have_http_status(:ok)
    snapshot = ticket.sla_snapshots.sole
    expect(response.parsed_body.fetch('snapshot')).to eq('id' => snapshot.id.to_s, 'version' => 1, 'permissions' => { 'show' => false })
    expect(response.body).not_to include(snapshot.payload_digest, 'test-contract', 'test-policy', 'coverage')
    get "#{base}/sla_snapshots/#{snapshot.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'denies readback and recording after the unit membership is revoked' do
    snapshot = JrcServiceDesk::RecordSlaSnapshotService.new(user_context: sd_context).call(ticket_id: ticket.id, attributes: sd_snapshot_attributes)
    sd_membership.update!(active: false)
    get "#{base}/sla_snapshots/#{snapshot.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(snapshot.payload_digest, 'test-contract')
    expect do
      post "#{base}/sla_snapshots", headers: headers, as: :json, params: { snapshot: sd_snapshot_attributes.merge(source_version: 'v2') }
    end.not_to change(JrcServiceDesk::SlaSnapshot, :count)
    expect(response).to have_http_status(:not_found)
  end

  it 'does not expand an administrator write or read into another ungranted unit' do
    other = create(:jrc_sd_ticket, unit: sd_other_unit)
    snapshot = create(:jrc_sd_snapshot, ticket: other)
    get "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/tickets/#{other.id}/sla_snapshots/#{snapshot.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    expect do
      post "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/tickets/#{other.id}/sla_snapshots", headers: headers, as: :json,
        params: { snapshot: sd_snapshot_attributes }
    end.not_to change(JrcServiceDesk::SlaSnapshot, :count)
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects a snapshot belonging to another account even when the local parent ticket is visible' do
    foreign = create(:jrc_sd_ticket, unit: sd_foreign_unit)
    snapshot = create(:jrc_sd_snapshot, ticket: foreign)
    get "#{base}/sla_snapshots/#{snapshot.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(snapshot.payload_digest, snapshot.source_reference)
    expect do
      post "#{base}/sla_snapshots", headers: headers, as: :json,
        params: { snapshot: sd_snapshot_attributes.merge(account_id: sd_foreign_account.id, unit_id: sd_foreign_unit.id, ticket_id: foreign.id) }
    end.not_to change(JrcServiceDesk::SlaSnapshot, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'does not accept a snapshot from another visible ticket through the current parent route' do
    other = sd_ticket(title: 'Other visible ticket')
    snapshot = create(:jrc_sd_snapshot, ticket: other)
    get "#{base}/sla_snapshots/#{snapshot.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(snapshot.payload_digest)
  end

  [[:version, 99], [:due_at, '2026-10-08T18:00:00Z'], [:expected_lock_version, 0],
   [:captured_at, '2026-10-08T12:00:00'], [:timezone, 'Invalid/Timezone'], [:calendar_conditions, []]].each do |field, value|
    it "rejects unsupported or invalid #{field} without partial native writes" do
      ticket
      expect do
        post "#{base}/sla_snapshots", headers: headers, as: :json, params: { snapshot: sd_snapshot_attributes.merge(field => value) }
      end.not_to change(JrcServiceDesk::SlaSnapshot, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(ticket.sla_milestones.count).to eq(0)
      expect(ticket.ticket_events.count).to eq(0)
      expect(JrcServiceDesk::SlaClock.where(ticket_id: ticket.id).count).to eq(0)
    end
  end

  it 'rejects credential fields without returning their contents or logging the unfiltered parameter value' do
    captured = []
    secret = 'fixture-only-sensitive-snapshot-key'
    subscriber = ActiveSupport::Notifications.subscribe('process_action.action_controller') do |*arguments|
      captured << ActiveSupport::Notifications::Event.new(*arguments).payload[:params]
    end
    expect do
      post "#{base}/sla_snapshots", headers: headers, as: :json,
        params: { snapshot: sd_snapshot_attributes.merge(contract_conditions: { nested: { api_key: secret } }) }
    end.not_to change(JrcServiceDesk::SlaSnapshot, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('code')).to eq('validation_failed')
    expect(response.body).not_to include(secret, 'api_key')
    expect(captured).not_to be_empty
    expect(captured.to_json).not_to include(secret)
    expect(ticket.sla_milestones.count).to eq(0)
    expect(ticket.ticket_events.count).to eq(0)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  it 'requires native authentication and rejects unsupported read query parameters' do
    snapshot = create(:jrc_sd_snapshot, ticket: ticket)
    get "#{base}/sla_snapshots/#{snapshot.id}"
    expect(response).to have_http_status(:unauthorized)
    get "#{base}/sla_snapshots/#{snapshot.id}", headers: headers, params: { include: 'all' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).not_to include(snapshot.payload_digest, snapshot.source_reference)
  end
end

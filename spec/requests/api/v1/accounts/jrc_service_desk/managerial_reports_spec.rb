# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk managerial report scope and filters', type: :request do
  include_context 'JRC Service Desk domain'
  let(:path) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/managerial_reports" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:opened) { Time.iso8601('2026-03-01T12:00:00Z') }

  before { sd_as_admin! }

  it 'blocks ordinary agents and preserves the existing operational report' do
    sd_account_user.update!(role: :agent)
    get path, headers: headers, params: { unit_id: sd_unit.id }
    expect(response).to have_http_status(:forbidden)
    get "#{path}/options", headers: headers
    expect(response).to have_http_status(:forbidden)
    get path.sub('managerial_reports', 'operational_reports'), headers: headers, params: { unit_id: sd_unit.id }
    expect(response).to have_http_status(:ok)
  end

  it 'partitions native, imported, and unknown origins before pagination, excluding old openings' do
    manual = sd_ticket(origin_channel: 'manual', opened_at: opened)
    portal = sd_ticket(origin_channel: 'portal', opened_at: opened)
    legacy = sd_ticket(origin_channel: 'legacy_import', opened_at: opened)
    other = sd_ticket(origin_channel: 'unclassified', opened_at: opened)
    sd_ticket(origin_channel: 'legacy_import', opened_at: opened - 1.year, created_at: opened)

    { 'all' => [manual, portal, legacy, other], 'native' => [manual, portal], 'legacy_import' => [legacy],
      'manual' => [manual], 'portal' => [portal], 'unknown' => [other] }.each do |origin, records|
      get path, headers: headers, params: { unit_id: sd_unit.id, origin: origin }
      expect(response).to have_http_status(:ok), response.body
      expect(response.parsed_body.fetch('items').pluck('id')).to match_array(records.map { |ticket| ticket.id.to_s })
    end
    expect(response.parsed_body.fetch('items').first).to include('origin' => 'unknown', 'origin_code' => 'unclassified')
    get path, headers: headers, params: { unit_id: sd_unit.id, per_page: 2, page: 2 }
    expect(response.parsed_body).to include('meta' => { 'total' => 4, 'page' => 2, 'per_page' => 2 })
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([portal.id.to_s, manual.id.to_s])
  end

  it 'applies inclusive local dates, permits future dates and keeps the opening cutoff for every date field' do
    sd_account.update!(reporting_timezone: 'America/Sao_Paulo')
    prior = sd_ticket(opened_at: Time.iso8601('2026-01-01T02:59:59Z'), created_at: opened, updated_at: opened)
    first = sd_ticket(opened_at: Time.iso8601('2026-01-01T03:00:00Z'), created_at: opened, updated_at: opened)
    last = sd_ticket(opened_at: Time.iso8601('2026-01-02T02:59:59Z'))
    sd_ticket(opened_at: Time.iso8601('2026-01-02T03:00:00Z'))
    future = sd_ticket(opened_at: Time.iso8601('2028-04-10T15:00:00Z'))
    get path, headers: headers, params: { unit_id: sd_unit.id, from: '2026-01-01', to: '2026-01-01' }
    expect(response.parsed_body.fetch('items').pluck('id')).to contain_exactly(first.id.to_s, last.id.to_s)
    %w[created_at updated_at].each do |field|
      get path, headers: headers, params: { unit_id: sd_unit.id, from: '2026-03-01', to: '2026-03-01', date_field: field }
      expect(response.parsed_body.fetch('items').pluck('id')).to include(first.id.to_s)
      expect(response.parsed_body.fetch('items').pluck('id')).not_to include(prior.id.to_s)
    end
    get path, headers: headers, params: { unit_id: sd_unit.id, from: '2028-04-10', to: '2028-04-10' }
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([future.id.to_s])
  end

  it 'combines filtering and supplies options only from authorized tickets' do
    allowed_team = create(:team, account: sd_account)
    other_team = create(:team, account: sd_account)
    queue = create(:jrc_sd_queue, unit: sd_unit, team: allowed_team)
    elsewhere = create(:jrc_sd_membership, unit: sd_other_unit, account_user: sd_account_user)
    sd_ticket(unit: sd_other_unit, team: other_team, priority: create(:jrc_sd_priority, unit: sd_other_unit),
              status: create(:jrc_sd_status, unit: sd_other_unit), created_by_membership: elsewhere, opened_at: opened)
    included = sd_ticket(team: allowed_team, queue: queue, opened_at: opened, origin_channel: 'manual')
    sd_ticket(team: allowed_team, queue: queue, opened_at: opened, origin_channel: 'portal', assignee_membership: sd_membership)
    get "#{path}/options", headers: headers, params: { unit_id: sd_unit.id, field: 'team_id', q: allowed_team.name.first(20) }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([allowed_team.id.to_s])
    get path, headers: headers, params: { unit_id: sd_unit.id, phase: 'open', team_id: allowed_team.id, queue_id: queue.id,
                                          origin: 'manual', assignee_membership_id: 'unassigned' }
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([included.id.to_s])
    expect(response.parsed_body.fetch('items').first).to include('requester' => sd_contact.name, 'assignee' => nil)
    expect(response.parsed_body.fetch('items').first).not_to have_key('description')
    get path, headers: headers, params: { unit_id: sd_unit.id, team_id: other_team.id }
    expect(response).to have_http_status(:not_found)
  end

  it 'applies the existing restrictions on teams and queues even to a native administrator' do
    team = create(:team, account: sd_account)
    queue = create(:jrc_sd_queue, unit: sd_unit, team: team)
    visible = sd_ticket(queue: queue, team: team, opened_at: opened)
    sd_ticket(opened_at: opened)
    grant = { 'queue_id' => queue.id, 'team_id' => team.id, 'permissions' => ['tickets_view'] }
    sd_membership.update!(restricted_supervision: true, supervision_grants: [grant])
    get path, headers: headers, params: { unit_id: sd_unit.id }
    expect(response).to have_http_status(:forbidden)

    grant['permissions'] << 'reports_view'
    sd_membership.update!(supervision_grants: [grant])
    get path, headers: headers, params: { unit_id: sd_unit.id }
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([visible.id.to_s])
    context = JrcServiceDesk::OperationalContext.new(sd_context)
    expect(context.managerial_reporting_allowed?(:indicators, unit: sd_unit)).to be(true)
    expect(context.managerial_reporting_allowed?(:export, unit: sd_unit)).to be(false)
  end

  it 'blocks foreign scope and rejects unsupported dates, origins and filters' do
    get path, headers: headers, params: { unit_id: sd_foreign_unit.id }
    expect(response).to have_http_status(:not_found)
    get path.sub("/accounts/#{sd_account.id}/", "/accounts/#{sd_foreign_account.id}/"), headers: headers, params: { unit_id: sd_foreign_unit.id }
    expect(response.status).to be_in([401, 403, 404])
    [{ from: '2025-12-31' }, { from: '2026-03-02', to: '2026-03-01' }, { date_field: 'description' },
     { q: 'ticket' }, { origin: 'fake' }].each do |invalid|
      get path, headers: headers, params: { unit_id: sd_unit.id }.merge(invalid)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end

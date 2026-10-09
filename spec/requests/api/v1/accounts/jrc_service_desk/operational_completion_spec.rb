# frozen_string_literal: true

require 'rails_helper'
require 'csv'

RSpec.describe 'Service Desk completion configuration and reports', type: :request do
  include_context 'JRC Service Desk domain'
  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token }

  before { sd_as_admin! }

  it 'publishes configuration and independently reads its persisted version and digest' do
    definition = { 'window_days' => 14, 'minimum_occurrences' => 2, 'group_by' => ['normalized_title'] }
    post "#{base}/operational_rules", params: { unit_id: sd_unit.id, kind: 'recurrence', definition: definition, enabled: false,
                                                expected_version: 0 }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    created = response.parsed_body.fetch('version')
    get "#{base}/operational_rules", params: { unit_id: sd_unit.id, kind: 'recurrence' }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('versions').first).to eq(created)
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'denies publication and report data to an ordinary agent' do
    sd_account_user.update!(role: :agent)
    get "#{base}/operational_rules", params: { unit_id: sd_unit.id, kind: 'recurrence' }, headers: headers
    expect(response).to have_http_status(:forbidden)
    get "#{base}/operational_reports", params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).not_to have_key('report')
  end

  it 'uses the same authorized cohort for reports and escaped CSV export' do
    first = sd_ticket(title: '=1+1')
    second = sd_ticket(title: 'Normal text')
    get "#{base}/operational_reports", params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').map { |row| row['id'] }).to match_array([first.id, second.id].map(&:to_s))
    expect(response.parsed_body.dig('report', 'fcr', 'value')).to be_nil
    expect(response.parsed_body.dig('report', 'reopen', 'events')).to eq(0)
    get "#{base}/operational_reports/export", params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('text/csv')
    rows = CSV.parse(response.body, headers: true)
    expect(rows.map { |row| row['number'] }).to match_array([first.id, second.id].map(&:to_s))
    expect(rows.find { |row| row['number'] == first.id.to_s }['title']).to eq("'=1+1")
    expect(Audited::Audit.where(associated: sd_unit, action: 'export').count).to eq(1)
  end

  it 'rejects foreign Unit, unsupported filters and timestamps without offsets' do
    get "#{base}/operational_reports", params: { unit_id: sd_foreign_unit.id }, headers: headers
    expect(response).to have_http_status(:not_found)
    get "#{base}/operational_reports", params: { unit_id: sd_unit.id, sql: 'anything' }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    get "#{base}/operational_reports", params: { unit_id: sd_unit.id, from: '2026-10-09' }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'counts exact recurrence suggestions without creating an incident or linking tickets' do
    tickets = [sd_ticket(title: 'Same defect'), sd_ticket(title: ' SAME DEFECT '), sd_ticket(title: 'Different')]
    definition = { 'window_days' => 14, 'minimum_occurrences' => 2, 'group_by' => ['normalized_title'] }
    JrcServiceDesk::PublishOperationalRulesService.new(user_context: sd_context).call(unit_id: sd_unit.id, kind: 'recurrence',
                                                                                      definition: definition, enabled: true, expected_version: 0)
    get "#{base}/recurrence_suggestions", params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('recurrence', 'groups').first['ticket_ids']).to match_array(tickets.first(2).map { |row| row.id.to_s })
    expect(JrcServiceDesk::Incident.count).to eq(0)
    expect(tickets.all? { |row| row.reload.incident_id.nil? }).to be(true)
  end
end

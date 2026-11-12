# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Native Service Desk satisfaction overview', type: :request do
  include_context 'Service Desk survey models V3'
  let(:path) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/satisfaction_reports" }
  let(:ticket) { sd_ticket }
  let(:closed_status) { create(:jrc_sd_status, unit: sd_unit, phase: 'closed', initial: false) }
  let(:model) do
    payload = survey_payload.deep_dup
    payload['kind'] = 'csat'
    payload['questions'].first.merge!('min' => 1, 'max' => 5)
    publish_survey_model(payload)
  end
  let(:survey) do
    model
    ticket.update!(status: closed_status)
    JrcRelationship::SurveyEngine.evaluate_event(source: ticket, event: 'closure', cycle_key: "overview:#{ticket.id}").survey.tap do |row|
      row.update!(score: 5, answers: { 'score' => 5 }, comment: '=Authorized comment', responded_at: Time.current, status: 'responded')
    end
  end

  it 'uses the published engine scores and does not invent a delivery for a public link' do
    survey
    get path, headers: survey_headers, params: { unit_id: sd_unit.id, period_basis: 'cohort' }
    expect(response).to have_http_status(:ok), response.body
    result = response.parsed_body
    expect(result.dig('summary', 'csat')).to eq(5.0)
    expect(result.dig('summary', 'response_count')).to eq(1)
    expect(result.dig('summary', 'delivery', 'sent_count')).to eq(0)
    expect(result.dig('summary', 'delivery', 'delivered_count')).to eq(0)
    expect(result['distribution'].find { |row| row['score'] == 5 }['count']).to eq(1)
    expect(result['items'].sole['ticket_id']).to eq(ticket.id.to_s)
    get "#{path}/export", headers: survey_headers, params: { unit_id: sd_unit.id, period_basis: 'cohort' }
    expect(response).to have_http_status(:ok), response.body
    expect(response.body).to include("'=Authorized comment")
  end

  it 'filters real responses and reports delivery as unavailable for a response-only date period' do
    survey
    get path, headers: survey_headers,
              params: { unit_id: sd_unit.id, period_basis: 'response', from: Date.current.iso8601, to: Date.current.iso8601 }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.dig('summary', 'delivery', 'available')).to be(false)
    get path, headers: survey_headers, params: { unit_id: sd_unit.id, type: 'nps' }
    expect(response.parsed_body.dig('meta', 'total')).to eq(0)
  end

  it 'honors current model report grants and rejects a foreign unit without changing responses' do
    survey
    model.definition.update!(settings: model.definition.settings.deep_merge('service_desk_model' => { 'permissions' => { 'share_reports' => false } }))
    get path, headers: survey_headers, params: { unit_id: sd_unit.id }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.dig('meta', 'total')).to eq(0)
    get path, headers: survey_headers, params: { unit_id: sd_foreign_unit.id }
    expect(response.status).to be_in([403, 404])
    expect(survey.reload.score).to eq(5)
  end
end

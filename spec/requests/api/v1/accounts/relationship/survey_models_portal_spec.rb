require 'rails_helper'

RSpec.describe 'V3 survey responses in the authenticated native customer portal', type: :request do
  include_context 'Service Desk survey models V3'
  let(:sd_contact) { create(:contact, account: sd_account, identifier: SecureRandom.uuid) }
  let(:widget) { create(:channel_widget, account: sd_account) }
  let(:identity) { create(:contact_inbox, contact: sd_contact, inbox: widget.inbox, hmac_verified: true) }
  let(:conversation) { create(:conversation, account: sd_account, contact: sd_contact, inbox: widget.inbox, contact_inbox: identity) }
  let(:service) do
    JrcServiceDesk::Service.create!(account: sd_account, unit: sd_unit, code: 'survey-portal', name: 'Synthetic support', active: true,
      default_priority: sd_priority, portal_inbox: widget.inbox, portal_execution_membership: sd_membership)
  end
  let(:ticket) { sd_ticket(service: service) }
  let(:headers) do
    { 'X-Auth-Token' => Widget::TokenService.new(payload: { source_id: identity.source_id, inbox_id: widget.inbox.id }).generate_token,
      'X-Service-Desk-Identifier' => sd_contact.identifier,
      'X-Service-Desk-Identity-Token' => OpenSSL::HMAC.hexdigest('sha256', widget.hmac_token, sd_contact.identifier) }
  end
  let(:row) { publish_survey_model }
  let(:survey) do
    row
    ticket.update!(status: create(:jrc_sd_status, unit: sd_unit, initial: false, phase: 'closed'))
    JrcRelationship::SurveyEngine.evaluate_event(source: ticket, event: 'closure', cycle_key: 'portal').survey
  end
  before do
    service.update!(portal_enabled: true)
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
  end

  it 'shows only the authenticated requester response and honors current sharing revocation' do
    JrcRelationship::SurveyResponse.new(survey).call(answers: { score: 9 })
    get "/api/v1/widget/service_desk/tickets/#{ticket.id}", params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('surveys')).to include(hash_including('id' => survey.id.to_s,
      'response' => [{ 'question' => 'Recommendation?', 'value' => 9 }]))
    expect(response.body).not_to include('execution_member_id', 'definition_snapshot', 'rule_snapshot', 'publication_key')
    payload = survey_payload.deep_dup
    payload['permissions']['customer_own_response'] = false
    draft = survey_editor.save(id: row.id, expected_version: row.reload.lock_version, payload: payload)
    survey_editor.publish(id: draft.id, expected_version: draft.lock_version, request_key: SecureRandom.uuid)
    get "/api/v1/widget/service_desk/tickets/#{ticket.id}", params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('surveys')).to be_empty
    expect(survey.reload.answers).to eq('score' => 9)
  end

  it 'denies a different verified customer even when the inbox is the same' do
    JrcRelationship::SurveyResponse.new(survey).call(answers: { score: 9 })
    other = create(:contact, account: sd_account, identifier: SecureRandom.uuid)
    link = create(:contact_inbox, contact: other, inbox: widget.inbox, hmac_verified: true)
    other_headers = { 'X-Auth-Token' => Widget::TokenService.new(payload: { source_id: link.source_id, inbox_id: widget.inbox.id }).generate_token,
      'X-Service-Desk-Identifier' => other.identifier,
      'X-Service-Desk-Identity-Token' => OpenSSL::HMAC.hexdigest('sha256', widget.hmac_token, other.identifier) }
    get "/api/v1/widget/service_desk/tickets/#{ticket.id}", params: { website_token: widget.website_token }, headers: other_headers
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('Recommendation?', 'response', '9')
  end
end

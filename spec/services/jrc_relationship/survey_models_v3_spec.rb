# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'Service Desk survey model execution and boundaries' do
  include_context 'Service Desk survey models V3'
  let(:closed_status) { create(:jrc_sd_status, unit: sd_unit, phase: 'closed', initial: false) }

  def closed_ticket
    sd_ticket.tap { |ticket| ticket.update!(status: closed_status) }
  end

  it 'enrolls once on closure and never on publication' do
    draft = publish_survey_model
    expect(JrcRelationship::Survey.where(account: sd_account)).to be_empty
    ticket = closed_ticket
    first = JrcRelationship::SurveyEngine.evaluate_event(source: ticket, event: 'closure', cycle_key: "v3:#{ticket.id}")
    expect(first.state).to eq('scheduled')
    expect(first.survey.definition_snapshot['questions']).to eq(draft.payload['questions'])
    replay = JrcRelationship::SurveyEngine.evaluate_event(source: ticket, event: 'closure', cycle_key: "v3:#{ticket.id}")
    expect(replay.survey_id).to eq(first.survey_id)
    expect(JrcRelationship::Survey.where(account: sd_account).count).to eq(1)
  end

  it 'does not select a closure model while the ticket is merely resolved' do
    publish_survey_model
    resolved = create(:jrc_sd_status, unit: sd_unit, phase: 'resolved', initial: false)
    ticket = sd_ticket.tap { |row| row.update!(status: resolved) }
    decision = JrcRelationship::SurveyEngine.evaluate_event(source: ticket, event: 'closure', cycle_key: "v3:#{ticket.id}")
    expect(decision.survey_id).to be_nil
  end

  it 'revalidates consent before portal availability' do
    publish_survey_model
    ticket = closed_ticket
    decision = JrcRelationship::SurveyEngine.evaluate_event(source: ticket, event: 'closure', cycle_key: "v3:#{ticket.id}")
    expect(decision.survey_id).to be_present
    sd_contact.update!(custom_attributes: { 'survey_consent' => false })
    JrcRelationship::SurveyDispatchJob.perform_now(decision.survey_id)
    expect(decision.survey.reload).to have_attributes(status: 'blocked', failure_code: 'contact_or_consent_revoked')
  end

  it 'normalizes configured CSAT bounds without changing the submitted answer' do
    data = survey_payload.deep_dup
    data['kind'] = 'csat'
    data['questions'].first.merge!('min' => 1, 'max' => 7)
    publish_survey_model(data)
    ticket = closed_ticket
    survey = JrcRelationship::SurveyEngine.evaluate_event(source: ticket, event: 'closure', cycle_key: "v3:#{ticket.id}").survey
    JrcRelationship::SurveyResponse.new(survey).call(answers: { score: 4 })
    expect(survey.reload.score).to eq(4)
    summary = JrcRelationship::SurveySummary.new(survey_context, JrcRelationship::Survey.where(id: survey.id)).call
    expect(summary[:csat]).to eq(3.0)
    expect(summary[:response_count]).to eq(1)
  end

  it 'applies sharing revocation to historic responses without rewriting their snapshot' do
    data = survey_payload.deep_dup
    data['permissions']['share_relationship'] = true
    draft = publish_survey_model(data)
    ticket = closed_ticket
    survey = JrcRelationship::SurveyEngine.evaluate_event(source: ticket, event: 'closure', cycle_key: "v3:#{ticket.id}").survey
    snapshot = survey.definition_snapshot.deep_dup
    rows = JrcRelationship::Survey.where(id: survey.id)
    expect(JrcRelationship::SurveyModelAccess.visible_scope(survey_context, rows, share: 'share_relationship')).to exist
    data['permissions']['share_relationship'] = false
    draft = survey_editor.save(id: draft.id, payload: data, expected_version: draft.lock_version)
    survey_editor.publish(id: draft.id, expected_version: draft.lock_version, request_key: SecureRandom.uuid)
    expect(JrcRelationship::SurveyModelAccess.visible_scope(survey_context, rows, share: 'share_relationship')).not_to exist
    expect(survey.reload.definition_snapshot).to eq(snapshot)
  end

  it 'preserves legacy fixed-scale validation' do
    model = JrcRelationship::SurveyDefinition.new(account: sd_account, name: 'Legacy', code: 'legacy', kind: 'csat', status: 'active',
      questions: [{ 'key' => 'score', 'text' => 'Question', 'type' => 'scale', 'required' => true, 'min' => 1, 'max' => 7 }])
    expect(model).not_to be_valid
  end

  it 'selects the next configured local window without inventing an overnight window' do
    window = { 'enabled' => true, 'timezone' => 'America/Sao_Paulo', 'days' => [1,2,3,4,5], 'start' => '08:00', 'end' => '18:00' }
    zone = ActiveSupport::TimeZone['America/Sao_Paulo']
    expect(JrcRelationship::SurveyModelRuntime.next_window(zone.local(2026,10,24,12), window)).to eq(zone.local(2026,10,26,8))
    expect(JrcRelationship::SurveyModelRuntime.next_window(zone.local(2026,10,26,9), window)).to eq(zone.local(2026,10,26,9))
    expect(JrcRelationship::SurveyModelRuntime.next_window(zone.local(2026,10,26,18), window)).to eq(zone.local(2026,10,27,8))
  end

  it 'does not leak a hidden shared response through its native CSAT adapter row' do
    data = survey_payload.deep_dup
    data['kind'] = 'csat'; data['questions'][0].merge!('min' => 1, 'max' => 5)
    publish_survey_model(data)
    ticket = closed_ticket
    survey = JrcRelationship::SurveyEngine.evaluate_event(source: ticket, event: 'closure', cycle_key: "v3:#{ticket.id}").survey
    inbox = create(:inbox, account: sd_account)
    conversation = create(:conversation, account: sd_account, contact: sd_contact, inbox: inbox)
    message = create(:message, account: sd_account, conversation: conversation, content_type: :input_csat)
    CsatSurveyResponse.create!(account: sd_account, conversation: conversation, contact: sd_contact, message: message, rating: 5)
    survey.update!(metadata: survey.metadata.merge('sent_message_id' => message.id))
    metric = JrcRelationship::SurveyMetrics.csat(context: survey_context, surveys: JrcRelationship::Survey.none, conversations: sd_account.conversations)
    expect(metric.count).to eq(0)
  end
end

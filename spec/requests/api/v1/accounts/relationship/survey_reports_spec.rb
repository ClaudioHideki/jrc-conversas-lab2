require 'rails_helper'
require 'csv'

RSpec.describe 'Authorized survey response reports', type: :request do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  let(:url) { "/api/v1/accounts/#{sd_account.id}/relationship" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:inbox) { create(:inbox, account: sd_account) }
  let(:conversation) { create(:conversation, account: sd_account, contact: sd_contact, inbox: inbox, status: :resolved) }
  let(:definition) do
    JrcRelationship::SurveyDefinition.create!(account: sd_account, name: 'Report NPS', code: 'report_nps', kind: 'nps', status: 'active',
                                              questions: [{ 'key' => 'rating', 'text' => 'Recommendation?', 'type' => 'scale',
                                                            'min' => 0, 'max' => 10, 'required' => true }])
  end
  let(:rule) do
    JrcRelationship::SurveyRule.create!(account: sd_account, name: 'Report policy', definition: definition,
                                        execution_member: sd_account_user, active: true, settings: { 'channel' => 'public_link' })
  end
  let(:survey) do
    rule
    JrcRelationship::SurveyEngine.evaluate_closure(source: conversation, cycle_key: 'report-cycle').survey
  end

  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_relationship')
    sd_contact.update!(custom_attributes: { 'survey_consent' => true })
    JrcRelationship::Configuration.create!(account: sd_account, rules: { survey_automation_enabled: true })
    create(:inbox_member, inbox: inbox, user: sd_user)
  end

  it 'applies identical filters to the list and CSV and preserves the immutable response' do
    JrcRelationship::SurveyResponse.new(survey).call(answers: { rating: 3 }, comment: 'Needs attention')
    filter = { type: 'nps', classification: 'detractor', treatment_status: 'untreated', source_type: 'Conversation',
               score_min: 0, score_max: 6, from: Date.current.iso8601, to: Date.current.iso8601 }
    get "#{url}/records/surveys", params: filter, headers: headers
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([survey.id])
    get "#{url}/survey_responses/export", params: filter, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('text/csv')
    rows = CSV.parse(response.body, headers: true)
    expect(rows.map { |row| row['id'].to_i }).to eq([survey.id])
    expect(rows.first['answers']).to eq('{"rating":3}')
    get "#{url}/survey_responses/export", params: filter.merge(classification: 'promoter'), headers: headers
    expect(CSV.parse(response.body, headers: true)).to be_empty
    expect(survey.reload.answers).to eq('rating' => 3)
  end

  it 'escapes formula-bearing strings and exports no private messages or rule credentials' do
    sd_contact.update!(name: '=HYPERLINK("https://example.test")')
    survey
    create(:message, account: sd_account, conversation: conversation, private: true, content: 'PRIVATE_MESSAGE_NOT_EXPORTED')
    JrcRelationship::SurveyResponse.new(survey).call(answers: { rating: 9 }, comment: "\t=1+1")
    survey.update!(treatment_status: 'treated', treatment_cause: '  +SUM(1,1)', treated_at: Time.current)
    get "#{url}/survey_responses/export", headers: headers
    rows = CSV.parse(response.body, headers: true)
    expect(rows.first['customer']).to start_with("'=")
    expect(rows.first['comment']).to eq("'\t=1+1")
    expect(rows.first['treatment_cause']).to eq("'  +SUM(1,1)")
    expect(response.body).not_to include('PRIVATE_MESSAGE_NOT_EXPORTED', 'execution_member_id', 'token_digest')
  end

  it 'rechecks native inbox grants and excludes responses from another account' do
    JrcRelationship::SurveyResponse.new(survey).call(answers: { rating: 8 }, comment: 'VISIBLE_RESPONSE')
    other = create(:conversation, account: sd_account, contact: sd_contact, status: :resolved)
    hidden = JrcRelationship::SurveyEngine.evaluate_closure(source: other, cycle_key: 'inaccessible-inbox').survey
    JrcRelationship::SurveyResponse.new(hidden).call(answers: { rating: 2 }, comment: 'INACCESSIBLE_INBOX_RESPONSE')
    sd_account_user.update!(role: :agent)
    get "#{url}/survey_responses/export", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('VISIBLE_RESPONSE')
    expect(response.body).not_to include('INACCESSIBLE_INBOX_RESPONSE')
    get "/api/v1/accounts/#{sd_foreign_account.id}/relationship/survey_responses/export", headers: headers
    expect(response).to have_http_status(:forbidden)
  end

  it 'excludes another operational unit after the source grant is revoked' do
    rule
    lc_publish
    own = sd_ticket
    lc_execute(own, 'resolve')
    own.reload
    own_survey = JrcRelationship::SurveyEngine.evaluate_closure(source: own, cycle_key: 'own-unit').survey
    JrcRelationship::SurveyResponse.new(own_survey).call(answers: { rating: 8 }, comment: 'OWN_UNIT_RESPONSE')
    other_membership = create(:jrc_sd_membership, unit: sd_other_unit, account_user: sd_account_user)
    other_statuses = lc_statuses.transform_values do |status|
      create(:jrc_sd_status, unit: sd_other_unit, phase: status.phase, initial: status.initial)
    end
    ids = lc_statuses.to_h { |key, status| [status.id, other_statuses.fetch(key).id] }
    definition = lc_definition.deep_dup
    definition['transitions'].each do |transition|
      transition['from_status_ids'].map! { |id| ids.fetch(id) }
      transition['to_status_id'] = ids.fetch(transition['to_status_id'])
    end
    definition['pause_reasons'].each { |reason| reason['status_ids'].map! { |id| ids.fetch(id) } }
    JrcServiceDesk::PublishLifecyclePolicyService.new(user_context: sd_context).call(unit_id: sd_other_unit.id,
                                                                                     attributes: {
                                                                                       name: 'Other unit fixture', enabled: true,
                                                                                       expected_version: 0, definition: definition
                                                                                     })
    other = sd_ticket(unit: sd_other_unit, created_by_membership: other_membership, status: other_statuses.fetch(:open),
                      priority: create(:jrc_sd_priority, unit: sd_other_unit))
    lc_execute(other, 'resolve')
    other.reload
    hidden = JrcRelationship::SurveyEngine.evaluate_closure(source: other, cycle_key: 'other-unit').survey
    JrcRelationship::SurveyResponse.new(hidden).call(answers: { rating: 2 }, comment: 'OTHER_UNIT_RESPONSE')
    other_membership.update!(active: false)
    sd_account_user.update!(role: :agent)
    get "#{url}/survey_responses/export", params: { source_type: 'JrcServiceDesk::Ticket' }, headers: headers
    expect(response.body).to include('OWN_UNIT_RESPONSE')
    expect(response.body).not_to include('OTHER_UNIT_RESPONSE')
    get "#{url}/survey_responses/export", params: { unit_id: sd_other_unit.id }, headers: headers
    expect(CSV.parse(response.body, headers: true)).to be_empty
  end

  it 'rejects malformed filters instead of ignoring them or widening the report' do
    get "#{url}/survey_responses/export", params: { source_type: 'User' }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    get "#{url}/survey_responses/export", params: { score_min: 'NaN' }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    get "#{url}/survey_responses/export", params: { contact_id: '1 OR 1=1' }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'filters a linked survey by model, rule and portfolio and keeps the filtered daily metrics consistent' do
    company = sd_account.master_companies.create!(name: 'Linked survey portfolio')
    sd_contact.update!(company_id: company.id)
    assignment = JrcRelationship::Assignment.create!(account: sd_account, company: company, owner: sd_user,
                                                     status: 'at_risk', settings: { 'complexity' => 'high' })
    JrcRelationship::SurveyDispatchJob.perform_now(survey.id)
    JrcRelationship::SurveyResponse.new(survey).call(answers: { rating: 3 })
    filters = { definition_id: definition.id, rule_id: rule.id, portfolio_owner_id: sd_user.id,
                portfolio_status: 'at_risk', complexity: 'high', assignment_id: assignment.id }
    get "#{url}/records/surveys", params: filters, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([survey.id])
    summary = response.parsed_body.fetch('meta').fetch('survey_report')
    expect(summary).to include('response_count' => 1, 'nps' => -100.0, 'csat' => nil, 'ces' => nil)
    expect(summary['trend']).to include(hash_including('kind' => 'nps', 'response_count' => 1, 'nps' => -100.0))
    get "#{url}/records/surveys", params: filters.merge(portfolio_status: 'inactive'), headers: headers
    expect(response.parsed_body.fetch('payload')).to be_empty
    expect(response.parsed_body.fetch('meta').fetch('survey_report')['response_count']).to eq(0)
    get "#{url}/survey_responses/export", params: filters.merge(definition_id: definition.id + 100_000), headers: headers
    expect(CSV.parse(response.body, headers: true)).to be_empty
  end
end

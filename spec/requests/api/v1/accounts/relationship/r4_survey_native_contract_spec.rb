require 'rails_helper'
require 'csv'

RSpec.describe 'R4 published survey preparation and delivery', type: :request do
  include_context 'JRC Service Desk domain'
  let(:url) { "/api/v1/accounts/#{sd_account.id}/relationship" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:company) { sd_account.master_companies.create!(name: 'Survey native company') }
  let(:assignment) { JrcRelationship::Assignment.create!(account: sd_account, company: company, owner: sd_user, status: 'active') }
  let(:channel) { create(:channel_whatsapp, account: sd_account) }
  let(:inbox) { create(:inbox, account: sd_account, channel: channel) }
  let(:conversation) { create(:conversation, account: sd_account, contact: sd_contact, inbox: inbox, assignee: sd_user, status: :resolved) }
  let(:questions) do
    [{ 'key' => 'rating', 'text' => 'Recommendation?', 'type' => 'scale', 'min' => 0, 'max' => 10, 'required' => true },
     { 'key' => 'choice', 'text' => 'Reason?', 'type' => 'choice', 'required' => true,
       'options' => [{ 'value' => 'service', 'label' => 'Service' }, { 'value' => 'product', 'label' => 'Product' }],
       'condition' => { 'question' => 'rating', 'operator' => 'lte', 'value' => 6 } }]
  end
  let(:definition) do
    JrcRelationship::SurveyDefinition.create!(account: sd_account, name: 'Published native NPS', code: 'r4_nps', kind: 'nps', status: 'active',
                                             questions: questions, settings: { 'recovery_enabled' => false })
  end
  let(:rule) do
    JrcRelationship::SurveyRule.create!(account: sd_account, name: 'Published native same-channel rule', definition: definition,
                                        execution_member: sd_account_user, active: true, matchers: { 'source_type' => 'Conversation' },
                                        settings: { 'channel' => 'same', 'frequency_days' => 0 })
  end
  let(:survey) do
    rule
    JrcRelationship::SurveyEngine.evaluate_closure(source: conversation, cycle_key: 'r4-published').survey.tap do |row|
      row.update!(status: 'available')
    end
  end
  let(:approved) do
    { 'name' => 'native_survey_link', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY', 'namespace' => 'native-test',
      'components' => [{ 'type' => 'BODY', 'text' => 'Pesquisa: {{1}}' }, { 'type' => 'FOOTER', 'text' => 'JRC' }] }
  end

  before do
    stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
      .with(headers: { 'D360-Api-Key' => 'test_key' })
      .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, 'https://waba.360dialog.io/v1/configs/templates')
      .with(headers: { 'D360-Api-Key' => 'test_key' })
      .to_return(status: 200, body: { waba_templates: [] }.to_json, headers: { 'Content-Type' => 'application/json' })
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    sd_contact.update!(company_id: company.id, email: 'survey@example.test', custom_attributes: { 'survey_consent' => true })
    JrcRelationship::Configuration.create!(account: sd_account, rules: { 'survey_automation_enabled' => true })
    create(:inbox_member, inbox: inbox, user: sd_user)
    assignment
  end

  def link
    get "#{url}/surveys/#{survey.id}/link", headers: headers
    expect(response).to have_http_status(:ok)
    response.parsed_body.fetch('url')
  end

  def delivery_fields(target_url = link)
    { conversation_id: conversation.id, content: "Pesquisa: #{target_url}",
      template_params: approved.slice('name', 'language', 'category', 'namespace').merge('processed_params' => { 'body' => { '1' => target_url } }) }
  end

  it 'compiles the exact published voice schema without sending a message' do
    id = survey.id
    expect do
      get "#{url}/surveys/#{id}/voice_preview", headers: headers
      expect(response).to have_http_status(:ok)
      result = response.parsed_body
      expect(result).to include('survey_id' => id, 'definition_version' => definition.version, 'dry_run' => true, 'persisted' => false,
                                'external_status' => 'not_configured')
      expect(result['questions'].first).to include('max_digits' => 2, 'terminator' => '#', 'max' => 10)
      expect(result['questions'][1]['options']).to include(hash_including('digit' => '2', 'value' => 'product'))
    end.not_to change(Message, :count)
  end

  it 'validates the same conditional voice parser without persisting answers or sending' do
    id = survey.id
    expect do
      post "#{url}/surveys/#{id}/voice_preview", params: { dry_run: true, inputs: { rating: '3', choice: '2' } }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['response_preview']).to include('answers' => { 'rating' => 3, 'choice' => 'product' },
                                                                  'classification' => 'detractor')
      post "#{url}/surveys/#{id}/voice_preview", params: { dry_run: true, inputs: { rating: '10' } }, headers: headers, as: :json
      expect(response.parsed_body['response_preview']['classification']).to eq('promoter')
    end.not_to change(Message, :count)
    expect(survey.reload).to have_attributes(responded_at: nil, answers: {})
  end

  it 'rejects non-dry-run, foreign inputs, missing conditional answers and revoked source access' do
    [{ dry_run: false, inputs: { rating: '10' } }, { dry_run: true, inputs: { rating: '3' } },
     { dry_run: true, inputs: { rating: '3', choice: '99' } }, { dry_run: true, inputs: { rating: '10', injected: 'data' } },
     { dry_run: true, inputs: { rating: { nested: '10' } } }].each do |fields|
      post "#{url}/surveys/#{survey.id}/voice_preview", params: fields, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    sd_contact.update!(custom_attributes: {})
    get "#{url}/surveys/#{survey.id}/voice_preview", headers: headers
    expect(response).to have_http_status(:forbidden)
    expect(survey.reload.responded_at).to be_nil
  end

  it 'publishes actual eligibility and delivery denominators and keeps response-period rates unavailable' do
    JrcRelationship::SurveyResponse.new(survey).call(answers: { rating: 10 })
    get "#{url}/records/surveys", params: { period_basis: 'cohort', from: Date.current.iso8601, to: Date.current.iso8601 }, headers: headers
    result = response.parsed_body.fetch('meta').fetch('survey_report')
    expect(result['delivery']).to include('eligible_count' => 1, 'eligible_answered_count' => 1, 'sent_count' => 0,
                                          'delivered_count' => 0, 'response_numerator' => 1, 'response_denominator' => 1,
                                          'response_rate' => 100.0, 'delivery_rate' => nil)
    expect(result['calculations']['nps']).to include('promoters' => 1, 'denominator' => 1)
    get "#{url}/records/surveys", params: { from: Date.current.iso8601 }, headers: headers
    expect(response.parsed_body.dig('meta', 'survey_report',
                                    'delivery')).to include('available' => false, 'reason' => 'response_period_requires_cohort')
  end

  it 'exports cohort enrollment, real status and eligibility without inventing provider delivery' do
    survey
    get "#{url}/survey_responses/export", params: { period_basis: 'cohort', from: Date.current.iso8601 }, headers: headers
    expect(response).to have_http_status(:ok)
    row = CSV.parse(response.body, headers: true).first
    expect(row['id'].to_i).to eq(survey.id)
    expect(row['delivery_status']).to eq('available')
    expect(row['eligible_decision_id'].to_i).to eq(JrcRelationship::SurveyDispatchDecision.find_by!(survey: survey).id)
    expect(row['period_basis']).to eq('cohort')
    expect(row['sent_at']).to be_nil
    expect(row['responded_at']).to be_nil
  end

  it 'uses exact inbox approved Meta params outside 24h and persists through the native MessageBuilder without provider I/O' do
    channel.update!(message_templates: [approved])
    expect(conversation.can_reply?).to be(false)
    fields = delivery_fields
    expect do
      post "#{url}/surveys/#{survey.id}/deliver", params: fields, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
    end.to change(Message, :count).by(1)
    message = Message.find(response.parsed_body.fetch('message_id'))
    expect({ account_id: message.account_id, conversation_id: message.conversation_id, inbox_id: message.inbox_id,
             contact_inbox_id: message.conversation.contact_inbox_id, template_params: message.additional_attributes['template_params'] })
      .to eq(account_id: sd_account.id, conversation_id: conversation.id, inbox_id: inbox.id,
             contact_inbox_id: conversation.contact_inbox_id, template_params: fields[:template_params])
    native = Whatsapp::TemplateProcessorService.new(channel: channel.reload, template_params: message.additional_attributes['template_params']).call
    expect({ identity: native.take(3), body: native.last.find { |part| part[:type] == 'body' } })
      .to eq(identity: approved.values_at('name', 'namespace', 'language'),
             body: { type: 'body', parameters: [{ type: 'text', text: fields[:template_params]['processed_params']['body']['1'] }] })
    expect({ status: survey.reload.status, sent_at: survey.sent_at, url: survey.metadata['survey_link_url'] })
      .to eq(status: 'queued', sent_at: nil, url: fields[:template_params]['processed_params']['body']['1'])
    JrcRelationship::SurveyMessageExecution.new(message).perform { message.update!(source_id: 'local-provider-proof-only') }
    expect(survey.reload.status).to eq('sent')
  end

  it 'replays an identical native template only once and rejects changed delivery intent' do
    channel.update!(message_templates: [approved])
    fields = delivery_fields
    post "#{url}/surveys/#{survey.id}/deliver", params: fields, headers: headers, as: :json
    first_id = response.parsed_body.fetch('message_id')
    expect do
      post "#{url}/surveys/#{survey.id}/deliver", params: fields, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['message_id']).to eq(first_id)
      fields[:content] = "Changed preview #{fields[:content]}"
      post "#{url}/surveys/#{survey.id}/deliver", params: fields, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end.not_to change(Message, :count)
    expect(survey.reload.metadata['sent_message_id']).to eq(first_id)
  end

  it 'blocks nonapproved, wrong locale, missing signed link and wrong inbox before creating a message' do
    channel.update!(message_templates: [approved])
    original_fields = delivery_fields
    fields = original_fields.deep_dup
    fields[:template_params]['language'] = 'en_US'
    foreign_url = URI.parse(original_fields[:content].delete_prefix('Pesquisa: '))
    foreign_url.host = 'foreign.example'
    expect do
      post "#{url}/surveys/#{survey.id}/deliver", params: fields, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      post "#{url}/surveys/#{survey.id}/deliver", params: delivery_fields('https://example.test/unrelated'), headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      post "#{url}/surveys/#{survey.id}/deliver", params: delivery_fields(foreign_url.to_s), headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      channel.update!(message_templates: [approved.merge('status' => 'PENDING')])
      post "#{url}/surveys/#{survey.id}/deliver", params: original_fields, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end.not_to change(Message, :count)
  end

  it 'rejects another inbox conversation instead of rerouting the exact published survey source' do
    channel.update!(message_templates: [approved])
    fields = delivery_fields
    other = create(:conversation, account: sd_account, contact: sd_contact, inbox: create(:inbox, account: sd_account))
    fields[:conversation_id] = other.id
    expect do
      post "#{url}/surveys/#{survey.id}/deliver", params: fields, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end.not_to change(Message, :count)
    expect(survey.reload.metadata['sent_message_id']).to be_nil
  end

  it 'accepts the exact official named parameter set independently of Hash order' do
    named = approved.merge('parameter_format' => 'NAMED', 'components' => [{ 'type' => 'BODY', 'text' => 'Survey for {{customer}}: {{survey_url}}' }])
    channel.update!(message_templates: [named])
    fields = delivery_fields
    fields[:template_params]['processed_params']['body'] = { 'survey_url' => link, 'customer' => 'Test customer' }
    post "#{url}/surveys/#{survey.id}/deliver", params: fields, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    message = Message.find(response.parsed_body.fetch('message_id'))
    native = Whatsapp::TemplateProcessorService.new(channel: channel.reload,
                                                    template_params: message.additional_attributes['template_params']).call.last
    signed_url = fields[:template_params]['processed_params']['body']['survey_url']
    expect(native.first[:parameters]).to include({ type: 'text', parameter_name: 'survey_url', text: signed_url },
                                                { type: 'text', parameter_name: 'customer', text: 'Test customer' })
  end

  it 'blocks a tampered signed-link origin at the queued provider boundary' do
    channel.update!(message_templates: [approved])
    post "#{url}/surveys/#{survey.id}/deliver", params: delivery_fields, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    message = Message.find(response.parsed_body.fetch('message_id'))
    survey.reload.update!(metadata: survey.metadata.merge('survey_link_origin' => 'https://foreign.example'))
    calls = 0
    JrcRelationship::SurveyMessageExecution.new(message).perform { calls += 1 }
    expect(calls).to eq(0)
    expect(message.reload).to be_failed
  end

  it 'rechecks approved template revocation after enqueue and never invokes a provider or free-form fallback' do
    channel.update!(message_templates: [approved])
    fields = delivery_fields
    post "#{url}/surveys/#{survey.id}/deliver", params: fields, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    message = Message.find(response.parsed_body.fetch('message_id'))
    channel.update!(message_templates: [approved.merge('status' => 'REJECTED')])
    calls = 0
    JrcRelationship::SurveyMessageExecution.new(message).perform { calls += 1 }
    expect(calls).to eq(0)
    expect(message.reload).to be_failed
    expect(survey.reload.status).to eq('blocked')
  end

  it 'keeps automated closed-window dispatch blocked without an explicitly configured approved template' do
    id = survey.id
    survey.update!(status: 'scheduled')
    version = survey.lock_version
    expect { JrcRelationship::SurveyDispatchJob.perform_now(id) }.not_to change(Message, :count)
    expect(survey.reload).to have_attributes(status: 'failed', failure_code: 'channel_configuration_invalid', attempts: 0)
    expect(survey.lock_version).to eq(version + 1)
  end

  it 'preserves an actual published response accepted after dispatch rollback instead of overwriting it in rescue' do
    id = survey.id
    survey.update!(status: 'scheduled')
    version = survey.lock_version
    reads = 0
    allow(JrcRelationship::Survey).to receive(:find_by).and_wrap_original do |lookup, *arguments|
      row = lookup.call(*arguments)
      reads += 1
      JrcRelationship::SurveyResponse.new(row).call(answers: { rating: 10 }) if reads == 2
      row
    end
    expect { JrcRelationship::SurveyDispatchJob.perform_now(id) }.not_to change(Message, :count)
    expect(survey.reload).to have_attributes(status: 'responded', classification: 'promoter', score: 10, attempts: 0)
    expect(survey.answers).to eq('rating' => 10)
    expect(survey.lock_version).to eq(version + 1)
  end
end

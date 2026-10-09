require 'rails_helper'

RSpec.describe 'Versioned official Meta survey rules', type: :request do
  include_context 'JRC Service Desk domain'
  let(:url) { "/api/v1/accounts/#{sd_account.id}/relationship" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:company) { sd_account.master_companies.create!(name: 'Template-rule company') }
  let(:channel) { create(:channel_whatsapp, account: sd_account) }
  let(:inbox) { create(:inbox, account: sd_account, channel: channel) }
  let(:conversation) { create(:conversation, account: sd_account, contact: sd_contact, inbox: inbox, assignee: sd_user, status: :resolved) }
  let(:definition) do
    JrcRelationship::SurveyDefinition.create!(account: sd_account, name: 'Published NPS template rule', code: 'rule_template_nps',
                                             kind: 'nps', status: 'active',
                                             questions: [{ 'key' => 'rating', 'text' => 'Recommendation?', 'type' => 'scale',
                                                           'min' => 0, 'max' => 10, 'required' => true }])
  end
  let(:approved) do
    { 'name' => 'approved_rule_survey', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY', 'namespace' => 'native-rule',
      'components' => [{ 'type' => 'BODY', 'text' => 'Pesquisa: {{1}}' }, { 'type' => 'FOOTER', 'text' => 'JRC' }] }
  end
  let(:template_params) do
    approved.slice('name', 'language', 'category', 'namespace').merge('processed_params' => { 'body' => { '1' => '{{survey_url}}' } })
  end
  let(:template_configuration) { { 'inbox_id' => inbox.id, 'content' => 'Pesquisa: {{survey_url}}', 'template_params' => template_params } }
  let(:rule_fields) do
    { name: 'Exact approved template rule', definition_id: definition.id, execution_member_id: sd_account_user.id, active: true,
      matchers: { source_type: 'Conversation' },
      settings: { channel: 'whatsapp', delivery_inbox_id: inbox.id, whatsapp_template: template_configuration, consent_required: true } }
  end
  let(:rule) do
    post "#{url}/survey_administration/rules", params: { record: rule_fields }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    JrcRelationship::SurveyRule.find(response.parsed_body.fetch('id'))
  end
  let(:survey) do
    rule
    JrcRelationship::SurveyEngine.evaluate_closure(source: conversation, cycle_key: 'configured-template-rule').survey
  end
  let(:queued_message) do
    JrcRelationship::SurveyDispatchJob.perform_now(survey.id)
    Message.find(survey.reload.metadata.fetch('sent_message_id'))
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
    sd_contact.update!(company_id: company.id, custom_attributes: { 'survey_consent' => true })
    JrcRelationship::Assignment.create!(account: sd_account, company: company, owner: sd_user, status: 'active')
    create(:inbox_member, inbox: inbox, user: sd_user)
    channel.update!(message_templates: [approved])
    JrcRelationship::Configuration.create!(account: sd_account, rules: { 'survey_automation_enabled' => true })
  end

  it 'saves an exact approved cached template in the immutable rule version and history, without delivering' do
    expect { rule }.not_to change(Message, :count)
    selection = rule.reload.settings.fetch('whatsapp_template')
    digest = JrcRelationship::SurveyTemplateSelection.new(account_id: sd_account.id, inbox: inbox, params: template_params).fingerprint
    expect(selection).to include('inbox_id' => inbox.id, 'template_fingerprint' => digest, 'template_params' => template_params)
    get "#{url}/survey_administration/rules/#{rule.id}/history", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').first.fetch('payload').dig('settings', 'whatsapp_template')).to eq(selection)
    expect(rule.version).to eq(1)
  end

  it 'queues the official template outside 24h with exact current conversation/contact_inbox and signed native URL' do
    expect(conversation.can_reply?).to be(false)
    message = queued_message
    signed_url = survey.metadata.fetch('survey_link_url')
    native = Whatsapp::TemplateProcessorService.new(channel: channel.reload, template_params: message.additional_attributes['template_params']).call
    expect(native.first(3)).to eq(approved.values_at('name', 'namespace', 'language'))
    expect(native.last.first.fetch(:parameters)).to eq([{ type: 'text', text: signed_url }])
    expect(message).to have_attributes(conversation_id: conversation.id, inbox_id: inbox.id, account_id: sd_account.id, private: false)
    expect(message.conversation.contact_inbox.id).to eq(conversation.contact_inbox.id)
    expect(message.content).to eq("Pesquisa: #{signed_url}")
    expect(message.content_attributes).to include('relationship_survey_template_revision' => rule.settings.dig('whatsapp_template', 'template_fingerprint'),
                                                'relationship_survey_link' => signed_url)
    expect(survey.reload).to have_attributes(status: 'queued', sent_at: nil, attempts: 1)
    expect(survey.metadata['message_payload_digest']).to eq(JrcRelationship::SurveyMessageExecution.payload_digest(message))
    expect(message.source_id).to be_nil
  end

  it 'replays the scheduled dispatch once and does not claim provider delivery' do
    message = queued_message
    expect { 2.times { JrcRelationship::SurveyDispatchJob.perform_now(survey.id) } }.not_to change(Message, :count)
    expect(survey.reload.metadata['sent_message_id']).to eq(message.id)
    expect(survey).to have_attributes(status: 'queued', attempts: 1, provider_id: nil, sent_at: nil, delivered_at: nil)
  end

  it 'keeps account automation OFF even with an approved template configured' do
    rule
    JrcRelationship::Configuration.find_by!(account: sd_account).update!(rules: { 'survey_automation_enabled' => false })
    expect do
      result = JrcRelationship::SurveyEngine.evaluate_closure(source: conversation, cycle_key: 'disabled-template-rule')
      expect(result.reason).to eq('automation_disabled')
      expect(result.survey_id).to be_nil
    end.not_to change(Message, :count)
  end

  it 'rejects unapproved, wrong-locale, incomplete-variable and missing-marker configurations without saving a rule' do
    invalid = [template_configuration.deep_dup, template_configuration.deep_dup, template_configuration.deep_dup, template_configuration.deep_dup]
    invalid[0]['template_params']['name'] = 'not_approved'
    invalid[1]['template_params']['language'] = 'en_US'
    invalid[2]['template_params']['processed_params']['body'] = { '2' => '{{survey_url}}' }
    invalid[3]['template_params']['processed_params']['body']['1'] = 'Unrelated value'
    expect do
      invalid.each do |configuration|
        fields = rule_fields.deep_dup
        fields[:settings][:whatsapp_template] = configuration
        post "#{url}/survey_administration/rules", params: { record: fields }, headers: headers, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end.not_to change(JrcRelationship::SurveyRule, :count)
  end

  it 'rejects an email inbox or another account inbox instead of selecting a different WABA' do
    [create(:inbox, :with_email, account: sd_account), create(:inbox, account: sd_foreign_account)].each do |other|
      fields = rule_fields.deep_dup
      fields[:settings][:delivery_inbox_id] = other.id
      fields[:settings][:whatsapp_template]['inbox_id'] = other.id
      post "#{url}/survey_administration/rules", params: { record: fields }, headers: headers, as: :json
      expect(response.status).to be_in([403, 404, 422])
    end
    expect(JrcRelationship::SurveyRule.where(account: sd_account).count).to eq(0)
  end

  it 'rejects an inbox without a synchronized cache in both rule configuration and the official manual delivery' do
    channel.update!(message_templates: nil)
    expect do
      post "#{url}/survey_administration/rules", params: { record: rule_fields }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end.not_to change(JrcRelationship::SurveyRule, :count)
    JrcRelationship::SurveyRule.create!(account: sd_account, definition: definition, execution_member: sd_account_user,
                                       name: 'Native manual rule', active: true, matchers: { 'source_type' => 'Conversation' },
                                       settings: { 'channel' => 'same' })
    native = JrcRelationship::SurveyEngine.evaluate_closure(source: conversation, cycle_key: 'missing-template-cache').survey
    get "#{url}/surveys/#{native.id}/link", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(native.reload.status).to eq('scheduled')
    native.update!(status: 'available')
    get "#{url}/surveys/#{native.id}/link", headers: headers
    expect(response).to have_http_status(:ok)
    signed_url = response.parsed_body.fetch('url')
    fields = template_params.deep_dup
    fields['processed_params']['body']['1'] = signed_url
    expect do
      post "#{url}/surveys/#{native.id}/deliver", params: { conversation_id: conversation.id, content: "Pesquisa: #{signed_url}",
                                                         template_params: fields }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end.not_to change(Message, :count)
    expect(native.reload.metadata['sent_message_id']).to be_nil
  end

  it 'does not silently adopt a changed approved template when editing another policy field' do
    id = rule.id
    original = rule.settings.deep_dup
    channel.update!(message_templates: [approved.merge('components' => [{ 'type' => 'BODY', 'text' => 'Changed: {{1}}' }])])
    patch "#{url}/survey_administration/rules/#{id}", params: { record: { name: 'Other change', version: 1, settings: original } },
                                                       headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(rule.reload).to have_attributes(version: 1, name: 'Exact approved template rule')
    expect(rule.settings).to eq(original)
  end

  it 'blocks a synchronized template change before queueing without a free-form fallback' do
    id = survey.id
    channel.update!(message_templates: [approved.merge('components' => [{ 'type' => 'BODY', 'text' => 'Changed: {{1}}' }])])
    expect { JrcRelationship::SurveyDispatchJob.perform_now(id) }.not_to change(Message, :count)
    expect(survey.reload).to have_attributes(status: 'failed', failure_code: 'channel_configuration_invalid', attempts: 0)
  end

  it 'blocks a same-name approved cache change after enqueue before the provider boundary' do
    message = queued_message
    channel.update!(message_templates: [approved.merge('components' => [{ 'type' => 'BODY', 'text' => 'Changed: {{1}}' }])])
    calls = 0
    JrcRelationship::SurveyMessageExecution.new(message).perform { calls += 1 }
    expect(calls).to eq(0)
    expect(message.reload).to be_failed
    expect(survey.reload.status).to eq('blocked')
  end

  it 'rejects a pending native template and never stores provider credentials in the versioned configuration' do
    channel.update!(message_templates: [approved.merge('status' => 'PENDING')])
    expect do
      post "#{url}/survey_administration/rules", params: { record: rule_fields }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end.not_to change(JrcRelationship::SurveyRule, :count)
    channel.update!(message_templates: [approved])
    expect(rule.settings.to_json).not_to include('test_key', channel.phone_number)
  end

  it 'binds the provider and non-secret WABA identity to the reviewed approved-template revision' do
    message = queued_message
    channel.update!(provider_config: channel.provider_config.merge('business_account_id' => 'changed-native-waba'))
    calls = 0
    JrcRelationship::SurveyMessageExecution.new(message).perform { calls += 1 }
    expect(calls).to eq(0)
    expect(message.reload).to be_failed
    expect(survey.reload.status).to eq('blocked')
  end

  it 'blocks consent revocation after enqueue and preserves the configured intent' do
    message = queued_message
    sd_contact.update!(custom_attributes: {})
    calls = 0
    JrcRelationship::SurveyMessageExecution.new(message).perform { calls += 1 }
    expect(calls).to eq(0)
    expect(survey.reload.failure_code).to eq('contact_or_consent_revoked')
    expect(survey.rule_snapshot.dig('settings', 'whatsapp_template', 'template_params')).to eq(template_params)
  end

  it 'blocks a revoked executor or inbox grant without finding another administrator' do
    message = queued_message
    sd_account_user.update!(role: :agent)
    InboxMember.where(inbox: inbox, user: sd_user).destroy_all
    calls = 0
    JrcRelationship::SurveyMessageExecution.new(message).perform { calls += 1 }
    expect(calls).to eq(0)
    expect(survey.reload.status).to eq('blocked')
    expect(message.reload).to be_failed
  end

  it 'binds template revision metadata to the existing payload digest' do
    message = queued_message
    old_digest = survey.metadata['message_payload_digest']
    message.update!(content_attributes: message.content_attributes.merge('relationship_survey_template_revision' => '0' * 64))
    expect(JrcRelationship::SurveyMessageExecution.payload_digest(message)).not_to eq(old_digest)
    calls = 0
    JrcRelationship::SurveyMessageExecution.new(message).perform { calls += 1 }
    expect(calls).to eq(0)
    expect(survey.reload.status).to eq('blocked')
  end

  it 'requires the current approved configuration at every rule version and blocks already scheduled old versions' do
    id = survey.id
    patch "#{url}/survey_administration/rules/#{rule.id}", params: { record: { name: 'Reviewed version two', version: 1 } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(rule.reload.version).to eq(2)
    expect { JrcRelationship::SurveyDispatchJob.perform_now(id) }.not_to change(Message, :count)
    expect(survey.reload).to have_attributes(status: 'blocked', failure_code: 'policy_changed')
  end

  it 'allows an explicitly reviewed template reselection and stores its new server revision' do
    original = rule.settings.dig('whatsapp_template', 'template_fingerprint')
    channel.update!(message_templates: [approved.merge('components' => [{ 'type' => 'BODY', 'text' => 'Reviewed: {{1}}' }])])
    fields = rule_fields.deep_dup.merge(version: 1)
    fields[:settings][:whatsapp_template]['content'] = 'Reviewed: {{survey_url}}'
    patch "#{url}/survey_administration/rules/#{rule.id}", params: { record: fields }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(rule.reload.version).to eq(2)
    expect(rule.settings.dig('whatsapp_template', 'template_fingerprint')).not_to eq(original)
  end

  it 'removes optional configuration through the native versioned settings update and keeps the original closed-window gate' do
    original = rule.settings.deep_dup.except('whatsapp_template')
    patch "#{url}/survey_administration/rules/#{rule.id}", params: { record: { version: 1, settings: original } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(rule.reload.effective_settings['whatsapp_template']).to be_nil
    decision = JrcRelationship::SurveyEngine.evaluate_closure(source: conversation, cycle_key: 'removed-template-rule')
    expect { JrcRelationship::SurveyDispatchJob.perform_now(decision.survey_id) }.not_to change(Message, :count)
    expect(decision.survey.reload).to have_attributes(status: 'failed', failure_code: 'channel_configuration_invalid')
  end
end

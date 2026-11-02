require 'rails_helper'
require 'csv'

RSpec.describe 'Survey models native persistence, security and ticket events', type: :request do
  include_context 'Service Desk survey models V3'
  include JrcServiceDeskLifecycleFixtures
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  let(:ticket) { sd_ticket }
  let(:model) { publish_survey_model }
  let(:closed_status) { create(:jrc_sd_status, unit: sd_unit, phase: 'closed', initial: false) }
  let(:enrollment) do
    model
    ticket.update!(status: closed_status)
    JrcRelationship::SurveyEngine.evaluate_event(source: ticket, event: 'closure', cycle_key: "integrated:#{ticket.id}").survey
  end
  let(:public_path) { "/jrc/relacionamento/pesquisas/#{enrollment.signed_id(purpose: :relationship_survey)}" }

  it 'requires authentication on lists, options, reads and writes' do
    row = model
    get survey_url, params: { unit_id: sd_unit.id }
    expect(response).to have_http_status(:unauthorized)
    get "#{survey_url}/options", params: { unit_id: sd_unit.id }
    expect(response).to have_http_status(:unauthorized)
    get "#{survey_url}/#{row.id}"
    expect(response).to have_http_status(:unauthorized)
    expect do
      patch "#{survey_url}/#{row.id}", params: { payload: survey_payload.merge('name' => 'Unauthorized'), lock_version: row.lock_version }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end.not_to(change { row.reload.attributes })
  end

  it 'rejects access to another Account without changing the original draft' do
    row = model
    other = create(:account_user, role: :administrator)
    auth = other.user.create_new_auth_token
    expect do
      get "#{survey_url}/#{row.id}", headers: auth
      expect(response).to have_http_status(:forbidden)
      patch "#{survey_url}/#{row.id}", headers: auth, as: :json,
        params: { payload: survey_payload.merge('name' => 'Other Account'), lock_version: row.lock_version }
      expect(response).to have_http_status(:forbidden)
    end.not_to(change { row.reload.attributes })
  end

  it 'does not allow an ordinary agent to elevate model grants or modify the draft' do
    row = model
    sd_account_user.update!(role: :agent)
    expect do
      patch "#{survey_url}/#{row.id}", headers: survey_headers, as: :json,
        params: { payload: survey_payload.merge('name' => 'Forbidden'), lock_version: row.lock_version }
      expect(response).to have_http_status(:forbidden)
    end.not_to(change { row.reload.attributes })
    get survey_url, params: { unit_id: sd_unit.id }, headers: survey_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload')).to be_empty
    expect(response.parsed_body.dig('meta', 'total')).to eq(0)
  end

  it 'intersects supervisor grants with the native configure permission and prevents ACL escalation' do
    payload = survey_payload.deep_dup
    payload['permissions']['edit_roles'] << 'supervisor'
    payload['permissions']['publish_roles'] << 'supervisor'
    row = publish_survey_model(payload)
    role = create(:custom_role, account: sd_account,
      permissions: %w[contact_manage jrc_relationship_view jrc_relationship_manage jrc_relationship_team jrc_relationship_configure
                      jrc_service_desk_module_view jrc_service_desk_tickets_view])
    sd_account_user.update!(role: :agent, custom_role: role)
    patch "#{survey_url}/#{row.id}", headers: survey_headers, as: :json,
      params: { payload: payload.merge('name' => 'Authorized supervisor draft'), lock_version: row.lock_version }
    expect(response).to have_http_status(:ok)
    changed = payload.deep_dup
    changed['permissions']['response_roles'] << 'agent'
    expect do
      patch "#{survey_url}/#{row.id}", headers: survey_headers, as: :json,
        params: { payload: changed, lock_version: row.reload.lock_version }
      expect(response).to have_http_status(:forbidden)
    end.not_to(change { row.reload.attributes })
    role.update!(permissions: %w[contact_manage jrc_relationship_view jrc_relationship_manage jrc_relationship_team
                                jrc_service_desk_module_view jrc_service_desk_tickets_view])
    post "#{survey_url}/#{row.id}/publish", headers: survey_headers, as: :json,
      params: { lock_version: row.reload.lock_version, request_key: SecureRandom.uuid }
    expect(response).to have_http_status(:forbidden)
  end

  it 'does not let an administrator with a restricted custom role bypass native configuration policy' do
    row = model
    role = create(:custom_role, account: sd_account, permissions: %w[contact_manage jrc_relationship_view
                                                                  jrc_service_desk_module_view jrc_service_desk_tickets_view])
    sd_account_user.update!(role: :administrator, custom_role: role)
    post "#{survey_url}/#{row.id}/publish", headers: survey_headers, as: :json,
      params: { lock_version: row.lock_version, request_key: SecureRandom.uuid }
    expect(response).to have_http_status(:forbidden)
  end

  it 'denies forged operator scope, immutable unit changes and unexpected payload fields' do
    row = model
    original = row.attributes.deep_dup
    patch "#{survey_url}/#{row.id}", headers: survey_headers, as: :json,
      params: { payload: survey_payload.merge('operator_id' => sd_foreign_operator.id), lock_version: row.lock_version }
    expect(response).to have_http_status(:forbidden)
    patch "#{survey_url}/#{row.id}", headers: survey_headers, as: :json,
      params: { payload: survey_payload.merge('unit_id' => sd_other_unit.id), lock_version: row.lock_version }
    expect(response).to have_http_status(:unprocessable_entity)
    patch "#{survey_url}/#{row.id}", headers: survey_headers, as: :json,
      params: { payload: survey_payload.merge('account_id' => sd_foreign_account.id), lock_version: row.lock_version }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(row.reload.attributes).to eq(original)
  end

  it 'rejects a conflicting code instead of overwriting an existing draft' do
    row = model
    expect do
      post survey_url, params: { payload: survey_payload.merge('name' => 'Collision') }, headers: survey_headers, as: :json
      expect(response).to have_http_status(:conflict)
    end.not_to change(JrcRelationship::SurveyModelDraft, :count)
    expect(row.reload.payload['name']).to eq('Synthetic feedback')
  end

  it 'rejects foreign team grants and disabled or foreign inboxes at publication' do
    payload = survey_payload.deep_dup
    payload['permissions']['team_ids'] = [create(:team, account: sd_foreign_account).id]
    row = survey_editor.save(payload: payload)
    post "#{survey_url}/#{row.id}/publish", params: { lock_version: row.lock_version, request_key: SecureRandom.uuid }, headers: survey_headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('errors')).to include(hash_including('step' => 4))
    payload = survey_payload.deep_dup.merge('code' => 'foreign_inbox')
    payload['channels']['email'] = { 'enabled' => true, 'inbox_id' => create(:inbox, :with_email, account: sd_foreign_account).id,
                                    'message' => 'Survey {{survey_link}}' }
    row = survey_editor.save(payload: payload)
    post "#{survey_url}/#{row.id}/publish", params: { lock_version: row.lock_version, request_key: SecureRandom.uuid }, headers: survey_headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('errors')).to include(hash_including('step' => 2))
  end

  it 'rolls back definition, rule, version and draft changes when publication fails' do
    row = survey_editor.save(payload: survey_payload.deep_dup)
    before = [JrcRelationship::SurveyDefinition.count, JrcRelationship::SurveyRule.count, JrcRelationship::SurveyVersion.count, row.attributes]
    allow_any_instance_of(JrcRelationship::SurveyAdministration).to receive(:save).and_wrap_original do |method, **args|
      raise ArgumentError, 'Synthetic rule persistence failure' if args[:kind] == 'rules'
      method.call(**args)
    end
    post "#{survey_url}/#{row.id}/publish", params: { lock_version: row.lock_version, request_key: SecureRandom.uuid }, headers: survey_headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect([JrcRelationship::SurveyDefinition.count, JrcRelationship::SurveyRule.count, JrcRelationship::SurveyVersion.count, row.reload.attributes]).to eq(before)
  end

  it 'rejects a reused publication key for a changed draft without rewriting the published snapshot' do
    row = model
    original = row.definition.snapshot.deep_dup
    previous_key = row.publication_key
    row = survey_editor.save(id: row.id, expected_version: row.lock_version, payload: survey_payload.merge('name' => 'Next version'))
    expect do
      post "#{survey_url}/#{row.id}/publish", headers: survey_headers, as: :json,
        params: { lock_version: row.lock_version, request_key: previous_key }
      expect(response).to have_http_status(:conflict)
    end.not_to change(JrcRelationship::SurveyVersion, :count)
    expect(row.definition.reload.snapshot).to eq(original)
  end

  it 'returns model options without channel credentials and leaves automation disabled when configured off' do
    configuration = JrcRelationship::Configuration.find_by!(account: sd_account)
    configuration.update!(rules: { 'survey_automation_enabled' => false })
    get "#{survey_url}/options", params: { unit_id: sd_unit.id }, headers: survey_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['automation_enabled']).to be(false)
    expect(response.parsed_body.keys).not_to include('password', 'token', 'api_key')
    publish_survey_model
    expect(JrcRelationship::SurveyEngine.enabled?(sd_account)).to be(false)
    expect(JrcRelationship::Survey.where(account: sd_account)).to be_empty
  end

  it 'publishes and executes an authorized manual model without shadowing Rails dispatch' do
    payload = survey_payload.deep_dup
    payload['rules']['event'] = 'manual'
    row = publish_survey_model(payload)
    post "#{survey_url}/#{row.id}/dispatch", params: { ticket_id: ticket.id }, headers: survey_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['state']).to eq('scheduled')
    expect(JrcRelationship::Survey.sole.contact).to eq(sd_contact)
    expect(JrcRelationship::Survey.sole.metadata['survey_trigger']).to eq('manual')
    expect do
      post "#{survey_url}/#{row.id}/dispatch", params: { ticket_id: ticket.id }, headers: survey_headers, as: :json
      expect(response).to have_http_status(:ok)
    end.not_to change(JrcRelationship::Survey, :count)
  end

  it 'requires a configured manual event and does not silently bypass a closure model' do
    row = model
    expect do
      post "#{survey_url}/#{row.id}/dispatch", params: { ticket_id: ticket.id }, headers: survey_headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end.not_to change(JrcRelationship::Survey, :count)
  end

  it 'renders and submits the versioned public form through real Rails then excludes a second response' do
    survey = enrollment
    JrcRelationship::SurveyDispatchJob.perform_now(survey.id)
    get public_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Recommendation?')
    post public_path, params: { answers: { score: 9 } }
    expect(response).to have_http_status(:ok)
    expect(survey.reload).to have_attributes(score: 9, status: 'responded', answers: { 'score' => 9 })
    post public_path, params: { answers: { score: 1 } }
    expect(response).to have_http_status(:not_found)
    expect(survey.reload.score).to eq(9)
  end

  it 'rejects expired, malformed and consent-revoked public tokens without storing answers' do
    survey = enrollment
    JrcRelationship::SurveyDispatchJob.perform_now(survey.id)
    sd_contact.update!(custom_attributes: { 'survey_consent' => false })
    get public_path
    expect(response).to have_http_status(:not_found)
    post public_path, params: { answers: { score: 9 } }
    expect(response).to have_http_status(:not_found)
    sd_contact.update!(custom_attributes: { 'survey_consent' => true })
    survey.reload.update!(expires_at: 1.minute.ago)
    get public_path
    expect(response).to have_http_status(:not_found)
    get '/jrc/relacionamento/pesquisas/invalid-token'
    expect(response).to have_http_status(:not_found)
    expect(survey.reload.responded_at).to be_nil
  end

  it 'rejects a link when its publication or executor has been revoked' do
    survey = enrollment
    JrcRelationship::SurveyDispatchJob.perform_now(survey.id)
    survey_editor.deactivate(id: model.id, expected_version: model.lock_version)
    get public_path
    expect(response).to have_http_status(:not_found)
    expect(survey.reload.responded_at).to be_nil
  end

  it 'filters responses and SQL exports with separate grants and current team membership' do
    team = create(:team, account: sd_account)
    payload = survey_payload.deep_dup
    payload['permissions'].merge!('team_ids' => [team.id], 'response_roles' => %w[administrator agent], 'report_roles' => ['administrator'])
    publish_survey_model(payload)
    ticket.update!(status: closed_status)
    survey = JrcRelationship::SurveyEngine.evaluate_event(source: ticket, event: 'closure', cycle_key: 'sql-grants').survey
    JrcRelationship::SurveyResponse.new(survey).call(answers: { score: 9 })
    create(:team_member, team: team, user: sd_user)
    sd_account_user.update!(role: :agent)
    get "/api/v1/accounts/#{sd_account.id}/relationship/records/surveys", headers: survey_headers,
      params: { source_type: 'JrcServiceDesk::Ticket', unit_id: sd_unit.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').pluck('id')).to include(survey.id)
    get "/api/v1/accounts/#{sd_account.id}/relationship/survey_responses/export", headers: survey_headers,
      params: { source_type: 'JrcServiceDesk::Ticket', unit_id: sd_unit.id }
    expect(response).to have_http_status(:ok)
    expect(CSV.parse(response.body, headers: true).map { |row| row['id'].to_i }).not_to include(survey.id)
    TeamMember.where(team: team, user: sd_user).destroy_all
    get "/api/v1/accounts/#{sd_account.id}/relationship/records/surveys", headers: survey_headers,
      params: { source_type: 'JrcServiceDesk::Ticket', unit_id: sd_unit.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').pluck('id')).not_to include(survey.id)
  end

  it 'reports configured CSAT/CES scales using PostgreSQL and keeps original scores unclassified without a threshold' do
    %w[csat ces].each do |kind|
      payload = survey_payload.deep_dup.merge('code' => "scale_#{kind}", 'kind' => kind)
      payload['questions'][0].merge!('min' => 1, 'max' => 7)
      payload['settings']['ces_direction'] = 'lower_is_better' if kind == 'ces'
      row = publish_survey_model(payload)
      ticket.update!(status: closed_status)
      rule = JrcRelationship::SurveyRule.find_by!(definition: row.definition)
      survey = JrcRelationship::SurveyEngine.evaluate_event(source: ticket, event: 'closure', cycle_key: kind, rule_id: rule.id).survey
      JrcRelationship::SurveyResponse.new(survey).call(answers: { score: 4 })
      expect(survey.reload.score).to eq(4)
      expect(survey.classification).to eq('unclassified')
    end
    get "/api/v1/accounts/#{sd_account.id}/relationship/records/surveys", headers: survey_headers,
      params: { source_type: 'JrcServiceDesk::Ticket', unit_id: sd_unit.id }
    expect(response).to have_http_status(:ok)
    report = response.parsed_body.dig('meta', 'survey_report')
    expect(report['normalization']).to be_present
    expect(report['csat']).to eq(3.0)
    expect(report['ces']).to eq(5.0)
  end

  it 'keeps closure committed on enqueue failure then recovers the native event idempotently' do
    model
    lc_publish
    expect(JrcRelationship::SurveyClosureJob).to receive(:perform_later).at_least(:once).and_raise(StandardError, 'Synthetic queue outage')
    lc_execute(ticket, 'resolve')
    lc_execute(ticket, 'close')
    expect(ticket.reload.status.phase).to eq('closed')
    expect(ticket.ticket_events.where(event_type: 'lifecycle_transitioned').count).to eq(2)
    expect(JrcRelationship::Survey.where(account: sd_account)).to be_empty
    JrcRelationship::SurveyEventRecovery.new(sd_account).call
    survey = JrcRelationship::Survey.where(account: sd_account).sole
    expect(survey.contact_id).to eq(ticket.requester_id)
    expect(survey.source_id).to eq(ticket.id)
    expect do
      JrcRelationship::SurveyEventRecovery.new(sd_account).call
      JrcRelationship::SurveyDispatchJob.perform_now(survey.id)
    end.not_to change(JrcRelationship::Survey, :count)
    expect(survey.reload.status).to eq('available')
  end

  it 'recovers a due scheduled survey without retrying an uncertain provider result' do
    survey = enrollment
    clear_enqueued_jobs
    JrcRelationship::SurveyEventRecovery.new(sd_account).call
    expect(enqueued_jobs.any? { |job| job[:job] == JrcRelationship::SurveyDispatchJob && job[:args] == [survey.id] }).to be(true)
    survey.update!(status: 'unknown', failure_code: 'delivery_result_unknown')
    clear_enqueued_jobs
    JrcRelationship::SurveyEventRecovery.new(sd_account).call
    expect(enqueued_jobs.none? { |job| job[:job] == JrcRelationship::SurveyDispatchJob }).to be(true)
  end

  it 'uses only the first verified public agent reply and keeps notes and incoming messages ineligible' do
    lc_publish
    payload = survey_payload.deep_dup
    payload['rules']['event'] = 'first_agent_response'
    publish_survey_model(payload)
    conversation = create(:conversation, account: sd_account, contact: sd_contact)
    create(:inbox_member, inbox: conversation.inbox, user: sd_user)
    JrcServiceDesk::LinkConversationService.new(user_context: sd_context).call(ticket_id: ticket.id, conversation_id: conversation.id)
    note = create(:message, account: sd_account, conversation: conversation, sender: sd_user, message_type: :outgoing,
      private: true, content: 'Synthetic note', status: :delivered, source_id: 'synthetic-private')
    incoming = create(:message, account: sd_account, conversation: conversation, sender: sd_contact, message_type: :incoming,
      private: false, content: 'Synthetic customer reply', status: :delivered, source_id: 'synthetic-incoming')
    [note, incoming].each do |message|
      JrcServiceDesk::FirstResponseJob.perform_now(message.id, JrcServiceDesk::NativeResponseRecorder.evidence(message.reload))
    end
    expect(ticket.ticket_events.where(event_type: 'first_response_observed')).to be_empty
    answer = create(:message, account: sd_account, conversation: conversation, sender: sd_user, message_type: :outgoing,
      private: false, content: 'Synthetic public reply', status: :delivered, source_id: 'synthetic-answer')
    2.times { JrcServiceDesk::FirstResponseJob.perform_now(answer.id, JrcServiceDesk::NativeResponseRecorder.evidence(answer.reload)) }
    event = ticket.ticket_events.find_by!(event_type: 'first_response_observed')
    2.times { JrcRelationship::SurveyResponseEventJob.perform_now(event.id) }
    expect(JrcRelationship::Survey.where(account: sd_account).count).to eq(1)
    expect(JrcRelationship::Survey.sole.metadata['survey_trigger']).to eq('first_agent_response')
  end

  it 'retains the configured executor when another authorized agent closes the ticket' do
    model
    closer = create(:account_user, account: sd_account, role: :administrator)
    lc_publish
    service = JrcServiceDesk::LifecycleTransitionService.new(user_context: { account: sd_account, user: closer.user, account_user: closer })
    %w[resolve close].each do |action|
      service.call(ticket_id: ticket.id, idempotency_key: SecureRandom.uuid,
        attributes: { rule_key: action, expected_lock_version: ticket.reload.lock_version, expected_policy_version_id: JrcServiceDesk::LifecycleSelector.new(ticket).applicable.id })
    end
    JrcRelationship::SurveyEventRecovery.new(sd_account).call
    expect(JrcRelationship::Survey.where(account: sd_account).sole.execution_member_id).to eq(sd_account_user.id)
  end

  it 'lets a delegated publisher review and publish without granting editing or another unit' do
    payload = survey_payload.deep_dup
    payload['permissions']['publish_roles'] << 'supervisor'
    row = publish_survey_model(payload)
    role = create(:custom_role, account: sd_account,
      permissions: %w[contact_manage jrc_relationship_view jrc_relationship_manage jrc_relationship_team jrc_relationship_configure
                      jrc_service_desk_module_view jrc_service_desk_tickets_view])
    sd_account_user.update!(role: :agent, custom_role: role)
    get "#{survey_url}/#{row.id}", headers: survey_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('permissions')).to include('edit' => false, 'publish' => true)
    expect do
      patch "#{survey_url}/#{row.id}", headers: survey_headers, as: :json,
        params: { payload: payload.merge('name' => 'Forbidden edit'), lock_version: row.lock_version }
      expect(response).to have_http_status(:forbidden)
    end.not_to(change { row.reload.payload })
    post "#{survey_url}/#{row.id}/publish", headers: survey_headers, as: :json,
      params: { lock_version: row.lock_version, request_key: SecureRandom.uuid }
    expect(response).to have_http_status(:ok)
    sd_membership.update!(active: false)
    get "#{survey_url}/#{row.id}", headers: survey_headers
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects malformed draft types without persisting a payload that would break the editor' do
    [{ 'kind' => {} }, { 'questions' => [17] }, { 'active' => {} }, { 'channels' => { 'email' => [] } }].each do |invalid|
      expect do
        post survey_url, params: { payload: survey_payload.deep_dup.merge(invalid) }, headers: survey_headers, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end.not_to change(JrcRelationship::SurveyModelDraft, :count)
    end
  end
end

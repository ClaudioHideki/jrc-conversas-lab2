# frozen_string_literal: true
# Native integration fixtures; run only in an isolated test database after the additive migration.
RSpec.shared_context 'Service Desk survey models V3' do
  include_context 'JRC Service Desk domain'
  let(:survey_context) { JrcRelationship::Context.new(sd_account_user) }
  let(:survey_editor) { JrcRelationship::SurveyModelEditor.new(survey_context) }
  let(:survey_headers) { sd_user.create_new_auth_token }
  let(:survey_url) { "/api/v1/accounts/#{sd_account.id}/relationship/survey_models" }
  let(:survey_payload) do
    {
      'code' => 'service_feedback', 'name' => 'Synthetic feedback', 'description' => 'Test only',
      'kind' => 'nps', 'active' => true, 'unit_id' => sd_unit.id, 'operator_id' => sd_operator.id,
      'questions' => [{ 'key' => 'score', 'text' => 'Recommendation?', 'type' => 'scale', 'required' => true, 'min' => 0, 'max' => 10 }],
      'settings' => { 'thank_you' => 'Thanks', 'ces_direction' => 'higher_is_better' },
      'channels' => { 'whatsapp' => { 'enabled' => false }, 'email' => { 'enabled' => false }, 'public_link' => { 'enabled' => true } },
      'rules' => { 'event' => 'closed', 'delay_minutes' => 0, 'frequency_days' => 0, 'expires_hours' => 168,
                   'priority' => 100, 'consent_required' => true, 'execution_member_id' => sd_account_user.id,
                   'channel_order' => %w[whatsapp email public_link], 'send_window' => { 'enabled' => false } },
      'permissions' => { 'team_ids' => [], 'edit_roles' => ['administrator'], 'publish_roles' => ['administrator'],
                         'response_roles' => ['administrator'], 'report_roles' => ['administrator'],
                         'share_relationship' => false, 'share_reports' => true, 'customer_own_response' => true }
    }
  end
  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    sd_contact.update!(custom_attributes: { 'survey_consent' => true })
    JrcRelationship::Configuration.create!(account: sd_account, rules: { 'survey_automation_enabled' => true })
  end
  def publish_survey_model(payload = survey_payload)
    draft = survey_editor.save(payload: payload.deep_dup)
    survey_editor.publish(id: draft.id, expected_version: draft.lock_version, request_key: SecureRandom.uuid)
  end
end

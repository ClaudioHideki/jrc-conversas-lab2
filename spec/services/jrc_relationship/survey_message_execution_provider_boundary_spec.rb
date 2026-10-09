require 'rails_helper'

RSpec.describe JrcRelationship::SurveyMessageExecution do
  include_context 'JRC Service Desk domain'
  let(:inbox) { create(:inbox, :with_email, account: sd_account, csat_survey_enabled: true) }
  let(:conversation) { create(:conversation, account: sd_account, contact: sd_contact, inbox: inbox, assignee: sd_user, status: :resolved) }
  let(:definition) do
    JrcRelationship::SurveyDefinition.create!(account: sd_account, name: 'CSAT frozen', code: 'native_csat', kind: 'csat', status: 'active',
                                              questions: [{ 'key' => 'rating', 'text' => 'Published CSAT question', 'type' => 'scale',
                                                            'min' => 1, 'max' => 5, 'required' => true }])
  end
  let(:rule) do
    JrcRelationship::SurveyRule.create!(account: sd_account, name: 'Native rule', definition: definition, execution_member: sd_account_user,
                                        active: true, matchers: { 'source_type' => 'Conversation' }, settings: { 'channel' => 'same' })
  end
  let(:survey) do
    rule
    decision = JrcRelationship::SurveyEngine.evaluate_closure(source: conversation, cycle_key: 'native-cycle')
    JrcRelationship::SurveyDispatchJob.perform_now(decision.survey_id)
    decision.survey.reload
  end
  let(:message) { Message.find(survey.metadata.fetch('sent_message_id')) }

  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    sd_contact.update!(email: 'survey-customer@example.test', custom_attributes: { 'survey_consent' => true })
    JrcRelationship::Configuration.create!(account: sd_account, rules: { survey_automation_enabled: true })
  end

  it 'persists one native input with snapshot wording and queued status, without claiming it was sent' do
    expect(message).to be_input_csat
    expect(message.content).to eq('Published CSAT question')
    expect(survey.reload.status).to eq('queued')
    expect(survey.sent_at).to be_nil
    expect(conversation.messages.where(content_type: :input_csat).count).to eq(1)
    JrcRelationship::SurveyDispatchJob.perform_now(survey.id)
    expect(conversation.messages.where(content_type: :input_csat).count).to eq(1)
  end

  it 'claims dispatch once and requires provider evidence for sent and delivered states' do
    boundary = described_class.new(message)
    calls = 0
    2.times do
      boundary.perform do
        calls += 1
        expect(survey.reload.status).to eq('dispatching')
        message.update!(source_id: 'verified-provider-id')
      end
    end
    expect(calls).to eq(1)
    expect(survey.reload.status).to eq('sent')
    expect(survey.provider_id).to eq('verified-provider-id')
    message.update!(status: :delivered)
    JrcRelationship::SurveyReceiptJob.perform_now(message.id)
    expect(survey.reload.status).to eq('delivered')
    expect(survey.delivered_at).to be_present
  end

  it 'revalidates consent between enqueue and provider I/O without invoking the provider' do
    message
    sd_contact.update!(custom_attributes: {})
    calls = 0
    described_class.new(message).perform { calls += 1 }
    expect(calls).to eq(0)
    expect(survey.reload.status).to eq('blocked')
    expect(message.reload).to be_failed
  end

  it 'blocks an altered recipient or payload before provider I/O' do
    message.update!(content: 'Tampered published text')
    calls = 0
    described_class.new(message).perform { calls += 1 }
    expect(calls).to eq(0)
    expect(survey.reload.failure_code).to eq('message_payload_changed')
  end

  it 'permits physical membership revocation and blocks the queued dispatch while preserving its snapshot' do
    message
    original_member_id = sd_account_user.id
    JrcServiceDesk::UnitMembership.where(account_user_id: original_member_id).delete_all
    expect { sd_account_user.destroy! }.not_to raise_error
    expect(survey.reload.execution_member_id).to be_nil
    expect(survey.rule_snapshot['execution_member_id']).to eq(original_member_id)
    calls = 0
    described_class.new(message).perform { calls += 1 }
    expect(calls).to eq(0)
    expect(survey.reload.status).to eq('blocked')
    expect(survey.failure_code).to eq('execution_member_missing')
  end

  it 'fails closed for unknown or foreign survey tags' do
    unknown = create(:message, account: sd_account, conversation: conversation, message_type: :outgoing,
                               content_attributes: { relationship_survey_id: 9_999_999 })
    expect(described_class.applies?(unknown)).to be(true)
    calls = 0
    described_class.new(unknown).perform { calls += 1 }
    expect(calls).to eq(0)
    expect(unknown.reload).to be_failed
  end

  it 'blocks altered HTML, CC recipients and provider template payloads before I/O' do
    message.update!(content_attributes: message.content_attributes.merge('email' => { 'html_content' => { 'full' => '<p>Other payload</p>' } },
                                                                         'cc_emails' => ['unapproved@example.test']),
                    additional_attributes: { 'template_params' => { 'name' => 'other_template' } })
    calls = 0
    described_class.new(message).perform { calls += 1 }
    expect(calls).to eq(0)
    expect(survey.reload.failure_code).to eq('message_payload_changed')
  end

  it 'records unknown external effects without exposing exception text or resending on retry' do
    calls = 0
    2.times do
      described_class.new(message).perform do
        calls += 1
        raise 'Private provider credential detail'
      end
    end
    expect(calls).to eq(1)
    expect(survey.reload.status).to eq('unknown')
    expect(survey.failure_code).to eq('provider_result_unknown')
    expect(survey.attributes.to_json).not_to include('Private provider credential detail')
  end

  it 'links the native response to one shared response and one CSAT aggregate denominator' do
    response = CsatSurveyResponse.create!(account: sd_account, conversation: conversation, message: message, contact: sd_contact, rating: 4)
    JrcRelationship::SurveyEngine.native_csat_response(response)
    expect(survey.reload.score).to eq(4)
    metrics = JrcRelationship::SurveyMetrics.csat(context: JrcRelationship::Context.new(sd_account_user),
                                                  surveys: JrcRelationship::Survey.where(account: sd_account),
                                                  conversations: sd_account.conversations)
    expect(metrics.count).to eq(1)
    expect(metrics.average(:rating)).to eq(4)
  end
end

require 'rails_helper'

RSpec.describe JrcRelationship::SurveyEngine do
  include_context 'JRC Service Desk domain'
  let(:company) { sd_account.master_companies.create!(name: 'Survey customer') }
  let(:assignment) { JrcRelationship::Assignment.create!(account: sd_account, company: company, owner: sd_user, status: 'active') }
  let(:context) { JrcRelationship::Context.new(sd_account_user) }
  let(:configuration) { JrcRelationship::Configuration.create!(account: sd_account, rules: { survey_automation_enabled: true }) }
  let(:conversation) { create(:conversation, account: sd_account, contact: sd_contact, assignee: sd_user, status: :resolved) }
  let(:definition) do
    JrcRelationship::SurveyDefinition.create!(account: sd_account, name: 'Published NPS', code: 'shared_nps', kind: 'nps', status: 'active',
                                              questions: [{ 'key' => 'rating', 'text' => 'How likely are you to recommend us?',
                                                            'type' => 'scale', 'min' => 0, 'max' => 10, 'required' => true },
                                                          { 'key' => 'reason', 'text' => 'What should improve?', 'type' => 'text', 'required' => true,
                                                            'condition' => { 'question' => 'rating', 'operator' => 'lte', 'value' => 6 } }],
                                              settings: { 'recovery_enabled' => false })
  end
  let(:rule) do
    JrcRelationship::SurveyRule.create!(account: sd_account, name: 'Closure rule', definition: definition, execution_member: sd_account_user,
                                        active: true, matchers: { 'source_type' => 'Conversation' }, settings: { 'channel' => 'public_link' })
  end

  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm', 'jrc_projects')
    sd_contact.update!(company_id: company.id, custom_attributes: { 'survey_consent' => true })
    assignment
  end

  it 'keeps automation OFF without inspecting or scheduling the origin' do
    rule
    expect do
      decision = described_class.evaluate_closure(source: conversation, cycle_key: 'cycle-1')
      expect(decision.state).to eq('skipped')
      expect(decision.reason).to eq('automation_disabled')
    end.not_to change(JrcRelationship::Survey, :count)
    expect(JrcRelationship::SurveyDispatchDecision.count).to eq(1)
  end

  it 'deduplicates an actual closure and publishes a public link without sending a message' do
    configuration
    rule
    conversation
    expect do
      first = described_class.evaluate_closure(source: conversation, cycle_key: 'cycle-1')
      second = described_class.evaluate_closure(source: conversation, cycle_key: 'cycle-1')
      expect(first.id).to eq(second.id)
      expect(first.state).to eq('scheduled')
      JrcRelationship::SurveyDispatchJob.perform_now(first.survey_id)
      expect(first.survey.reload.status).to eq('available')
      expect(first.survey).to have_attributes(source_id: conversation.id, rule_version: rule.version)
      expect(first.survey.definition_snapshot['questions']).to eq(definition.questions)
    end.not_to change(Message, :count)
    expect(JrcRelationship::Survey.where(account: sd_account).count).to eq(1)
  end

  it 'rejects consent, blocked contacts and incomplete interactions with recorded reasons' do
    configuration
    rule
    sd_contact.update!(custom_attributes: {})
    expect(described_class.evaluate_closure(source: conversation, cycle_key: 'no-consent').reason).to eq('consent_missing')
    sd_contact.update!(blocked: true)
    expect(described_class.evaluate_closure(source: conversation, cycle_key: 'blocked').reason).to eq('contact_blocked')
    conversation.update!(status: :open)
    expect(described_class.evaluate_closure(source: conversation, cycle_key: 'incomplete').reason).to eq('interaction_not_completed')
    expect(JrcRelationship::Survey.where(account: sd_account)).not_to exist
  end

  it 'selects the explicit policy actor and blocks a missing actor without choosing an administrator' do
    configuration
    revocable_actor = create(:account_user, account: sd_account, role: :administrator)
    rule.update!(execution_member: revocable_actor)
    revocable_actor.destroy!
    expect(rule.reload.execution_member_id).to be_nil
    expect(sd_account.account_users).to exist(id: sd_account_user.id, role: :administrator)
    decision = described_class.evaluate_closure(source: conversation, cycle_key: 'missing-actor')
    expect(decision.state).to eq('blocked')
    expect(decision.reason).to eq('execution_member_missing')
    expect(JrcRelationship::Survey.where(account: sd_account)).not_to exist
  end

  it 'blocks foreign account actors and rechecks the actor before delayed dispatch' do
    configuration
    rule
    foreign = create(:account_user, account: sd_foreign_account)
    result = described_class.new(source: conversation, cycle_key: 'foreign', member: foreign).call
    expect(result.reason).to eq('execution_member_missing')
    allowed = described_class.evaluate_closure(source: conversation, cycle_key: 'allowed')
    sd_account.disable_features!('jrc_relationship')
    JrcRelationship::SurveyDispatchJob.perform_now(allowed.survey_id)
    expect(allowed.survey.reload.status).to eq('blocked')
    expect(allowed.survey.failure_code).to eq('policy_disabled')
  end

  it 'applies frequency across different closure cycles and retains the original immutable decision' do
    configuration
    rule.update!(settings: { 'channel' => 'public_link', 'frequency_days' => 30, 'frequency_scope' => 'contact' })
    first = described_class.evaluate_closure(source: conversation, cycle_key: 'cycle-1')
    second = described_class.evaluate_closure(source: conversation, cycle_key: 'cycle-2')
    expect(first.state).to eq('scheduled')
    expect(second.reason).to eq('frequency_exceeded')
    expect { first.update!(reason: 'changed') }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'selects the most specific rule and lets an explicit disabled override stop dispatch' do
    configuration
    generic = JrcRelationship::SurveyRule.create!(account: sd_account, name: 'Account default', definition: definition,
                                                  execution_member: sd_account_user, active: true, matchers: {},
                                                  settings: { 'channel' => 'public_link' })
    rule.update!(active: false)
    decision = described_class.evaluate_closure(source: conversation, cycle_key: 'disabled-override')
    expect(decision.reason).to eq('rule_disabled')
    expect(decision.rule_id).to eq(rule.id)
    expect(decision.rule_id).not_to eq(generic.id)
  end

  it 'versions edits and keeps previously dispatched wording, scale and origin immutable' do
    configuration
    rule
    survey = described_class.evaluate_closure(source: conversation, cycle_key: 'frozen').survey
    administration = JrcRelationship::SurveyAdministration.new(context)
    questions = definition.questions.deep_dup
    questions.first['text'] = 'New wording'
    administration.save(kind: 'definitions', id: definition.id, expected_version: definition.version, attributes: { questions: questions })
    expect(definition.reload.version).to eq(2)
    expect(JrcRelationship::SurveyVersion.where(entity_type: definition.class.name,
                                                entity_id: definition.id).pluck(:version)).to contain_exactly(
                                                  1, 2
                                                )
    expect(survey.reload.questions.first['text']).to eq('How likely are you to recommend us?')
    expect { survey.update!(definition_snapshot: definition.snapshot) }.to raise_error(ActiveRecord::RecordInvalid)
    expect do
      administration.save(kind: 'definitions', id: definition.id, expected_version: 1, attributes: { name: 'Stale' })
    end.to raise_error(ActiveRecord::StaleObjectError)
  end

  it 'validates bounded scales and conditional required answers and stores one immutable response' do
    configuration
    rule
    survey = described_class.evaluate_closure(source: conversation, cycle_key: 'answers').survey
    responder = JrcRelationship::SurveyResponse.new(survey)
    expect { responder.call(answers: { rating: 11, reason: 'Outside' }) }.to raise_error(ArgumentError, /scale/)
    expect { responder.call(answers: { rating: 3 }) }.to raise_error(ArgumentError, /Required/)
    responder.call(answers: { rating: 9, reason: 'Hidden answer' }, comment: 'Feedback')
    expect(survey.reload.answers).to eq('rating' => 9)
    expect(survey.classification).to eq('promoter')
    expect { responder.call(answers: { rating: 6, reason: 'Again' }) }.to raise_error(ArgumentError, /already/)
    expect { survey.update!(score: 5) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(JrcRelationship::RiskCase.where(assignment: assignment)).not_to exist
  end

  it 'correlates enabled detractor recovery once with real risk, action and Agenda' do
    configuration
    definition.update!(settings: { 'recovery_enabled' => true, 'recovery_sla_hours' => 24 })
    rule
    survey = described_class.evaluate_closure(source: conversation, cycle_key: 'recover').survey
    responder = JrcRelationship::SurveyResponse.new(survey)
    responder.call(answers: { rating: 3, reason: 'Slow response' }, native_response_id: 123)
    responder.call(answers: { rating: 3, reason: 'Slow response' }, native_response_id: 123)
    risk = JrcRelationship::RiskCase.find(survey.reload.metadata.fetch('recovery_risk_id'))
    action = JrcRelationship::Action.find_by!(source_key: "risk:#{risk.id}")
    expect(risk.source_key).to eq("survey-response:#{survey.id}:recovery")
    expect(action.activity).to be_present
    expect(JrcRelationship::RiskCase.where(source_key: risk.source_key).count).to eq(1)
    expect(JrcRelationship::Action.where(source_key: action.source_key).count).to eq(1)
  end

  it 'requires an explicit QBR recipient and never uses the first company contact' do
    configuration
    rule.update!(matchers: { 'source_type' => 'JrcRelationship::Qbr' })
    qbr = JrcRelationship::Qbr.create!(account: sd_account, assignment: assignment, title: 'QBR', scheduled_at: Time.current,
                                       status: 'completed', summary: 'Minutes')
    expect(described_class.evaluate_closure(source: qbr, cycle_key: 'qbr-1').reason).to eq('contact_missing')
    qbr.update!(contact: sd_contact)
    expect(described_class.evaluate_closure(source: qbr, cycle_key: 'qbr-2').state).to eq('scheduled')
  end

  it 'requires an explicit delivery inbox for a configured alternate channel' do
    rule.settings = { 'channel' => 'email' }
    expect(rule).not_to be_valid
    expect(rule.errors[:settings]).to include('alternate channel requires an explicit account inbox')
  end

  it 'blocks a changed source recipient before making an immutable survey available' do
    configuration
    rule
    pending = described_class.evaluate_closure(source: conversation, cycle_key: 'changed-recipient').survey
    replacement = create(:contact, account: sd_account, custom_attributes: { 'survey_consent' => true })
    conversation.update!(contact: replacement)
    expect { JrcRelationship::SurveyDispatchJob.perform_now(pending.id) }.not_to change(Message, :count)
    expect(pending.reload.status).to eq('blocked')
    expect(pending.failure_code).to eq('recipient_changed')
    expect(pending.contact_id).to eq(sd_contact.id)
  end
end

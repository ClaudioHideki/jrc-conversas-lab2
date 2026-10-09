require 'rails_helper'

RSpec.describe JrcRelationship::CustomerTimeline do
  include_context 'JRC Service Desk domain'
  let(:company) { sd_account.master_companies.create!(name: 'Timeline customer') }
  let(:assignment) { JrcRelationship::Assignment.create!(account: sd_account, company: company, owner: sd_user, status: 'active') }
  let(:context) { JrcRelationship::Context.new(sd_account_user) }
  let(:inbox) { create(:inbox, account: sd_account) }
  let(:conversation) { create(:conversation, account: sd_account, contact: sd_contact, inbox: inbox, assignee: sd_user, status: :resolved) }
  let(:definition) do
    JrcRelationship::SurveyDefinition.create!(account: sd_account, name: 'Timeline NPS', code: 'timeline_nps', kind: 'nps', status: 'active',
                                              questions: [{ 'key' => 'rating', 'text' => 'Recommendation?', 'type' => 'scale',
                                                            'min' => 0, 'max' => 10, 'required' => true }],
                                              settings: { 'recovery_enabled' => true })
  end
  let(:rule) do
    JrcRelationship::SurveyRule.create!(account: sd_account, name: 'Timeline policy', definition: definition, active: true,
                                        execution_member: sd_account_user, settings: { 'channel' => 'public_link', 'frequency_days' => 0 })
  end

  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm', 'jrc_projects')
    sd_contact.update!(company_id: company.id, custom_attributes: { 'survey_consent' => true })
    assignment
    create(:inbox_member, inbox: inbox, user: sd_user)
    JrcRelationship::Configuration.create!(account: sd_account, rules: { 'survey_automation_enabled' => true })
  end

  def answered_survey(source = conversation, cycle: 'timeline-cycle')
    rule
    survey = JrcRelationship::SurveyEngine.evaluate_closure(source: source, cycle_key: cycle).survey
    JrcRelationship::SurveyDispatchJob.perform_now(survey.id)
    JrcRelationship::SurveyResponse.new(survey).call(answers: { rating: 3 }, comment: 'ANSWER_CONTENT_NOT_IN_TIMELINE')
  end

  def timeline(customer)
    JrcCustomers::Timeline.new(context: customer, account: sd_account, user: sd_user).call
  end

  it 'links an actual response to its native conversation and idempotent recovery risk and action' do
    survey = answered_survey
    links = JrcRelationship::SurveyLinks.new(context, survey).call.index_by { |link| link[:kind] }
    expect(links.fetch('conversation')[:route]).to include(name: 'inbox_conversation', params: { accountId: sd_account.id,
                                                                                                 conversation_id: conversation.display_id })
    expect(links.fetch('risk')[:id]).to eq(survey.metadata['recovery_risk_id'])
    expect(links.fetch('action')[:id]).to eq(survey.metadata['recovery_action_id'])
    expect(links.fetch('risk')[:route][:query]).to include(record_id: survey.metadata['recovery_risk_id'])
    expect(JrcRelationship::RiskCase.where(source_key: "survey-response:#{survey.id}:recovery").count).to eq(1)
  end

  it 'adds real survey events to Customer360 without disclosing answers or private conversation messages' do
    survey = answered_survey
    private_message = create(:message, account: sd_account, conversation: conversation, private: true, content: 'PRIVATE_TIMELINE_MESSAGE')
    customer = assignment.customer_context(sd_account_user)
    result = timeline(customer)
    events = result[:payload].select { |event| event[:source] == 'relationship_survey_response' }
    expect(events).to include(hash_including(id: survey.id, title: 'Survey answered', resource_type: 'JrcRelationship::Survey'))
    expect(result.to_json).not_to include('ANSWER_CONTENT_NOT_IN_TIMELINE', 'PRIVATE_TIMELINE_MESSAGE', 'answers', 'rule_snapshot')
    expect(result[:payload]).not_to include(hash_including(source: 'message', id: private_message.id))
  end

  it 'excludes another customer survey and rechecks inbox grants for response and decision history' do
    own = answered_survey
    other_contact = create(:contact, account: sd_account, custom_attributes: { 'survey_consent' => true })
    other_source = create(:conversation, account: sd_account, contact: other_contact, inbox: inbox, assignee: sd_user, status: :resolved)
    other = answered_survey(other_source, cycle: 'other-customer-cycle')
    result = timeline(assignment.customer_context(sd_account_user))
    expect(result[:payload]).to include(hash_including(source: 'relationship_survey_response', id: own.id))
    expect(result[:payload]).not_to include(hash_including(source: 'relationship_survey_response', id: other.id))
    sd_account_user.update!(role: :agent)
    InboxMember.where(inbox: inbox, user: sd_user).destroy_all
    customer = assignment.customer_context(sd_account_user.reload)
    expect(customer.timeline_sources.fetch('relationship_survey_response').first).not_to exist
    expect(customer.timeline_sources.fetch('relationship_survey_decision').first).not_to exist
  end

  it 'keeps the core Customer360 available when relationship access is revoked' do
    answered_survey
    sd_account.disable_features!('jrc_relationship')
    customer = assignment.customer_context(sd_account_user)
    expect(customer.overview[:capabilities][:relationship]).to be(false)
    expect(customer.overview[:contacts]).to eq(1)
    expect(timeline(customer)[:payload]).not_to include(hash_including(source: 'relationship_survey_response'))
  end

  it 'filters native playbook execution history in SQL after its activity grant is revoked' do
    book = JrcRelationship::Playbook.create!(account: sd_account, name: 'Timeline playbook', trigger_kind: 'health', active: true,
                                             steps: [{ 'kind' => 'activity', 'title' => 'Authorized follow-up', 'after_days' => 1,
                                                       'step_key' => 'follow-up' }])
    JrcRelationship::Playbooks.new(context).run!(assignment, 'health', playbook_id: book.id)
    customer = assignment.customer_context(sd_account_user)
    expect(customer.timeline_sources.fetch('relationship_playbook_execution').first).to exist
    sd_account.disable_features!('jrc_crm')
    customer = assignment.customer_context(sd_account_user.reload)
    expect(customer.timeline_sources.fetch('relationship_playbook_execution').first).not_to exist
  end

  it 'preserves the immutable response and blocks recovery after the configured executor loses the origin grant' do
    rule
    survey = JrcRelationship::SurveyEngine.evaluate_closure(source: conversation, cycle_key: 'revoked-before-response').survey
    JrcRelationship::SurveyDispatchJob.perform_now(survey.id)
    sd_account_user.update!(role: :agent)
    InboxMember.where(inbox: inbox, user: sd_user).destroy_all
    expect do
      JrcRelationship::SurveyResponse.new(survey).call(answers: { rating: 3 }, comment: 'Retain original customer response')
    end.not_to change(JrcRelationship::RiskCase, :count)
    expect(survey.reload).to have_attributes(status: 'responded', score: 3, answers: { 'rating' => 3 })
    expect(survey.metadata).to include('recovery_status' => 'blocked_access')
    expect(survey.metadata).not_to have_key('recovery_risk_id')
    expect(assignment.actions.where(kind: 'retention')).not_to exist
    expect { survey.update!(score: 9) }.to raise_error(ActiveRecord::RecordInvalid)
  end
end

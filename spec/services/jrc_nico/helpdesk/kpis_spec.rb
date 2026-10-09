require 'rails_helper'

RSpec.describe JrcNico::Helpdesk::Kpis do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'Synthetic KPI company') }
  let(:ticket) { sd_ticket(company_id: company.id) }
  let(:definition) do
    value = JrcNico::Helpdesk::Definition.defaults.merge('unit_ids' => [sd_unit.id], 'company_ids' => [company.id],
                                                         'operator_ids' => [sd_account_user.id])
    value['roles']['n2'] = [sd_account_user.id]
    value['rules']['R01']['recipients'] = [sd_account_user.id]
    value
  end
  let(:policy) do
    JrcNico::Helpdesk::PolicyVersion.create!(account: sd_account, author: sd_account_user, number: 1, state: 'published', enabled: true,
                                             published_at: Time.current, definition: definition,
                                             digest: JrcNico::Helpdesk::Definition.digest(definition))
  end
  let(:metrics) { described_class.new(member: sd_account_user, policy: policy, from: 30.days.ago).call[:metrics].index_by { |item| item[:key] } }

  before do
    sd_account.update!(custom_attributes: { 'nico_enabled' => true })
    sd_account.enable_features!('jrc_relationship', 'jrc_customer_master')
    sd_as_admin!
  end

  it 'exposes all seven formulas/windows and no invented zero when there are no observed denominators' do
    expect(metrics.keys).to eq(%w[K1 K2 K3 K4 K5 K6 K7])
    expect(metrics.values).to all(include(state: 'sem_dados', value: nil, numerator: nil))
    expect(metrics.values.map { |item| item[:formula] }).to all(be_present)
    expect(metrics.values.map { |item| item[:window] }).to all(include(:from, :until))
  end

  it 'includes queue lag in the five-minute reincidence alert KPI and counts confirmed native delivery only' do
    [10.minutes.ago, 3.minutes.ago].each_with_index do |at, index|
      event = JrcNico::Helpdesk::Event.create!(account: sd_account, actor: sd_account_user, policy_version: policy, ticket: ticket,
                                               rule_key: 'R01', correlation_key: "synthetic-latency-#{index}", detected_at: Time.current,
                                               evidence: { 'source_occurred_at' => at.iso8601(6) })
      JrcNico::Helpdesk::Delivery.new(source: event, recipient: sd_account_user, channel: 'nico').call
    end
    expect(metrics['K5']).to include(state: 'available', numerator: 1, denominator: 2, value: 50.0)
    expect(metrics['K5'][:evidence]).to include('queue_lag_included' => true, 'recipient_role' => 'n2')
  end

  [[[20, 40], 30.0], [[20, 40, 90], 40.0]].each do |durations, median|
    it "measures the median of #{durations.size} confirmed native delivery receipts" do
      travel_to Time.iso8601('2026-10-08T12:00:00Z') do
        receipts = durations.map.with_index do |seconds, index|
          event = JrcNico::Helpdesk::Event.create!(account: sd_account, actor: sd_account_user, policy_version: policy, ticket: ticket,
                                                 rule_key: 'R01', correlation_key: "synthetic-median-#{index}", detected_at: 1.second.ago,
                                                 evidence: { 'source_occurred_at' => seconds.seconds.ago.iso8601(6) })
          JrcNico::Helpdesk::Delivery.new(source: event, recipient: sd_account_user, channel: 'nico').call.reload
        end
        expect(receipts.map(&:state)).to all(eq('delivered'))
        expect(JrcNico::Notice.where(id: receipts.map(&:remote_id)).count).to eq(durations.size)
        expect(metrics['K5']).to include(state: 'available', numerator: durations.size, denominator: durations.size, value: 100.0)
        expect(metrics['K5'][:evidence]).to include('median_seconds' => median, 'maximum_seconds' => durations.max,
                                                  'p95_seconds' => durations.max)
        expect(metrics['K5'][:evidence]['elapsed_seconds']).to match_array(durations.map(&:to_f))
        expect(metrics['K5'][:evidence]['samples'].map { |sample| sample.fetch('receipt_id') }).to match_array(receipts.map(&:id))
      end
    end
  end

  it 'excludes unobserved fourteen-day windows and requests from the defect reopening denominator' do
    lc_publish
    request_ticket = sd_ticket(company_id: company.id)
    JrcNico::Helpdesk::TicketProfile.create!(account: sd_account, unit: sd_unit, ticket: request_ticket, company: company, case_kind: 'request')
    lc_execute(request_ticket, 'resolve')
    lc_execute(request_ticket, 'close')
    JrcNico::Helpdesk::TicketProfile.create!(account: sd_account, unit: sd_unit, ticket: ticket, company: company, case_kind: 'defect')
    lc_execute(ticket, 'resolve')
    lc_execute(ticket, 'close')
    expect(metrics['K2']).to include(state: 'sem_dados', denominator: 0, value: nil)
    expect(metrics['K1']).to include(state: 'available', numerator: 0, denominator: 2, value: 0.0)
    expect(metrics['K1'][:evidence]['coverage']).to include('covered_human' => 2, 'unknown' => 0)
  end

  it 'never reuses a sent survey from another closure cycle to inflate coverage' do
    lc_publish
    lc_execute(ticket, 'resolve')
    lc_execute(ticket, 'close')
    prepare_shared_survey(channel: 'email')
    decision = JrcRelationship::SurveyEngine.new(source: ticket.reload, cycle_key: 'unrelated-prior-cycle', member: sd_account_user).call
    expect(decision.state).to eq('scheduled')
    JrcRelationship::SurveyDispatchJob.perform_now(decision.survey_id)
    message = Message.find(decision.survey.reload.metadata.fetch('sent_message_id'))
    JrcRelationship::SurveyMessageExecution.new(message).perform { message.update!(source_id: 'synthetic-kpi-provider-receipt') }
    expect(decision.survey.reload.status).to eq('sent')
    expect(metrics['K7']).to include(state: 'available', numerator: 0, denominator: 1, value: 0.0)
  end

  it 'uses the immutable principal NPS scale even when its question key is rating instead of score' do
    lc_publish
    prepare_shared_survey(channel: 'public_link')
    lc_execute(ticket, 'resolve')
    lc_execute(ticket, 'close')
    cycle = "service-desk:ticket:#{ticket.id}:cycle:initial"
    decision = JrcRelationship::SurveyDispatchDecision.find_by!(account: sd_account, source_type: ticket.class.name,
                                                                source_id: ticket.id, cycle_key: cycle)
    expect(decision.state).to eq('scheduled')
    JrcRelationship::SurveyDispatchJob.perform_now(decision.survey_id)
    JrcRelationship::SurveyResponse.new(decision.survey).call(answers: { 'rating' => 3 })
    facts = JrcNico::Helpdesk::Facts.new(context: JrcNico::Helpdesk::Context.new(sd_account_user), policy: policy,
                                         ticket: ticket.reload, trigger: 'customer_return').call
    expect(facts).to include('survey_model' => 'nps', 'survey_scale' => '0-10', 'survey_score' => 3)
    rules = definition.deep_dup
    rules['rules']['R10']['enabled'] = true
    expect(JrcNico::Helpdesk::RuleDetector.new(definition: rules, facts: facts).call.map { |item| item[:rule_key] }).to include('R10')
  end

  it 'does not expose a foreign policy or revoked native ticket scope' do
    ticket
    sd_membership.update!(active: false)
    expect(metrics.values.map { |item| item[:denominator] }).to all(eq(0))
    foreign = instance_double(JrcNico::Helpdesk::PolicyVersion, account_id: sd_foreign_account.id)
    expect { described_class.new(member: sd_account_user, policy: foreign, from: 1.day.ago) }.to raise_error(Pundit::NotAuthorizedError)
  end

  def prepare_shared_survey(channel:)
    sd_account.enable_features!('jrc_crm')
    sd_contact.update!(company_id: company.id, email: 'kpi-survey@example.test', custom_attributes: { 'survey_consent' => true })
    settings = shared_survey_channel(channel)
    JrcRelationship::Assignment.create!(account: sd_account, company: company, owner: sd_user, status: 'active')
    JrcRelationship::Configuration.create!(account: sd_account, rules: { survey_automation_enabled: true })
    question = { 'key' => 'rating', 'text' => 'Rate this service', 'type' => 'scale', 'min' => 0, 'max' => 10, 'required' => true }
    survey_definition = JrcRelationship::SurveyDefinition.create!(account: sd_account, name: 'KPI NPS', code: 'kpi_nps', kind: 'nps',
                                                                  status: 'active', questions: [question])
    JrcRelationship::SurveyRule.create!(account: sd_account, name: 'KPI closure', definition: survey_definition, execution_member: sd_account_user,
                                        active: true, matchers: { 'source_type' => ticket.class.name }, settings: settings)
  end

  def shared_survey_channel(channel)
    settings = { 'channel' => channel }
    return settings unless channel == 'email'

    inbox = create(:inbox, :with_email, account: sd_account)
    create(:conversation, account: sd_account, contact: sd_contact, inbox: inbox, assignee: sd_user, status: :resolved)
    settings.merge('delivery_inbox_id' => inbox.id)
  end
end

require 'rails_helper'

RSpec.describe JrcRelationship::SurveyMetrics do
  include_context 'JRC Service Desk domain'
  let(:company) { sd_account.master_companies.create!(name: 'Metrics customer') }
  let(:assignment) { JrcRelationship::Assignment.create!(account: sd_account, company: company, owner: sd_user, status: 'active') }
  let(:context) { JrcRelationship::Context.new(sd_account_user) }
  let(:inbox) { create(:inbox, account: sd_account) }
  let(:conversation) { create(:conversation, account: sd_account, contact: sd_contact, inbox: inbox, assignee: sd_user, status: :resolved) }

  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    sd_contact.update!(company_id: company.id, custom_attributes: { 'survey_consent' => true })
    JrcRelationship::Configuration.create!(account: sd_account, rules: { 'survey_automation_enabled' => true })
    create(:inbox_member, inbox: inbox, user: sd_user)
    assignment
  end

  def definition(kind:, settings: {})
    min, max = kind == 'csat' ? [1, 5] : [0, 10]
    JrcRelationship::SurveyDefinition.create!(account: sd_account, name: "Published #{kind}", code: "r4_#{kind}_#{SecureRandom.hex(3)}",
                                              kind: kind, status: 'active', settings: settings,
                                             questions: [{ 'key' => 'rating', 'type' => 'scale', 'text' => 'Published wording',
                                                           'required' => true, 'min' => min, 'max' => max }])
  end

  def make_shared(model)
    rule = JrcRelationship::SurveyRule.create!(account: sd_account, name: 'Published rule', definition: model, active: true,
                                               execution_member: sd_account_user, settings: { 'channel' => 'public_link', 'frequency_days' => 0 })
    decision = JrcRelationship::SurveyEngine.evaluate_closure(source: conversation, cycle_key: "native-cycle-#{rule.id}")
    [decision, rule]
  end

  it 'counts a shared CSAT once alongside native CSAT and exposes both exact source rows in drilldown' do
    decision, = make_shared(definition(kind: 'csat'))
    survey = decision.survey
    JrcRelationship::SurveyResponse.new(survey).call(answers: { rating: 5 })
    message = create(:message, account: sd_account, conversation: conversation, content_type: :input_csat)
    native = CsatSurveyResponse.create!(account: sd_account, conversation: conversation, contact: sd_contact, message: message, rating: 3)
    metrics = described_class.csat(context: context, surveys: context.records(JrcRelationship::Survey),
                                                  conversations: sd_account.conversations)
    expect(metrics.count).to eq(2)
    expect(metrics.average(:rating)).to eq(4)
    drilldown = JrcRelationship::MetricDrilldown.new(context: context, scope: context.assignments).call(metric: 'csat')
    expect(drilldown).to include(value: 4.0, total: 2)
    expect(drilldown[:calculation]).to include(formula: 'average', denominator: 2)
    expect(drilldown[:payload]).to include(hash_including(source_type: 'JrcRelationship::Survey', id: survey.id),
                                           hash_including(source_type: 'CsatSurveyResponse', id: native.id))
    survey.update!(metadata: survey.metadata.merge('sent_message_id' => message.id))
    expect(described_class.csat(context: context, surveys: context.records(JrcRelationship::Survey),
                                               conversations: sd_account.conversations).count).to eq(1)
  end

  it 'excludes shared and native CSAT after the same current inbox grant is revoked' do
    decision, = make_shared(definition(kind: 'csat'))
    JrcRelationship::SurveyResponse.new(decision.survey).call(answers: { rating: 4 })
    sd_account_user.update!(role: :agent)
    inbox.inbox_members.where(user: sd_user).delete_all
    fresh = JrcRelationship::Context.new(sd_account_user.reload)
    result = JrcRelationship::MetricDrilldown.new(context: fresh, scope: fresh.assignments).call(metric: 'csat')
    expect(result[:total]).to eq(0)
    expect(result[:payload]).to eq([])
  end

  it 'uses the immutable lower-is-better CES definition for classification and health normalization' do
    model = definition(kind: 'ces', settings: { 'ces_direction' => 'lower_is_better', 'low_threshold' => 7 })
    decision, = make_shared(model)
    survey = decision.survey
    administration = JrcRelationship::SurveyAdministration.new(context)
    administration.save(kind: 'definitions', id: model.id, expected_version: model.version,
                        attributes: { settings: { 'ces_direction' => 'higher_is_better', 'low_threshold' => 3 } })
    JrcRelationship::SurveyResponse.new(survey).call(answers: { rating: 9 })
    expect(survey.reload.classification).to eq('low')
    expect(survey.definition_snapshot.dig('settings', 'ces_direction')).to eq('lower_is_better')
    signals = JrcRelationship::SatisfactionSignals.new(context, assignment, assignment.customer_context(sd_account_user),
                                                       context.configuration.effective_rules).call
    expect(signals).to include(ces_score: 9.0, ces_normalized: 10.0)
  end

  it 'validates explicit availability timezone and blocks enrollment before publication without allocating a survey' do
    model = definition(kind: 'nps', settings: { 'available_from' => 1.day.from_now.iso8601, 'available_until' => 3.days.from_now.iso8601 })
    before_count = JrcRelationship::Survey.count
    decision, = make_shared(model)
    expect(decision).to have_attributes(state: 'skipped', reason: 'definition_not_available')
    expect(JrcRelationship::Survey.count).to eq(before_count)
    model.settings = { 'available_from' => '2026-10-08T12:00:00' }
    expect(model).not_to be_valid
    model.settings = { 'available_from' => 2.days.from_now.iso8601, 'available_until' => 1.day.from_now.iso8601 }
    expect(model).not_to be_valid
  end

  it 'caps a real survey expiry at the pinned validity end and blocks delayed execution after expiry' do
    until_at = 2.hours.from_now.change(usec: 0)
    model = definition(kind: 'nps', settings: { 'available_until' => until_at.iso8601 })
    decision, = make_shared(model)
    expect(decision.survey.expires_at).to eq(until_at)
    travel_to(until_at + 1.second) do
      JrcRelationship::SurveyDispatchJob.perform_now(decision.survey_id)
      expect(decision.survey.reload.status).to eq('expired')
    end
  end

  it 'retains opening cohort financial numerators and discloses incomplete closing coverage' do
    complete = JrcRelationship::RevenueMetrics.call(opening: { 1 => 100_000, 2 => 50_000 }, closing: { 1 => 120_000, 2 => 0, 3 => 900_000 })
    expect(complete).to include(nrr: 80.0, gross_retention: 66.67, revenue_churn_cents: 50_000)
    expect(complete[:revenue_calculation]).to include(opening_cents: 150_000, closing_cents: 120_000, denominator_cents: 150_000,
                                                      retained_cents: 100_000, lost_cents: 50_000)
    incomplete = JrcRelationship::RevenueMetrics.call(opening: { 1 => 100_000, 2 => 50_000 }, closing: { 1 => 120_000 })
    expect(incomplete[:nrr]).to be_nil
    expect(incomplete[:revenue_calculation]).to include(opening_customers: 2, closing_customers: 1, reason: 'closing_cohort_incomplete')
  end
end

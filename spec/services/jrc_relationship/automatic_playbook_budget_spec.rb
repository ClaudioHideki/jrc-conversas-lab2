require 'rails_helper'

RSpec.describe JrcRelationship::AutomaticPlaybookBudget, type: :request do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:context) { JrcRelationship::Context.new(member) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:configuration) do
    JrcRelationship::Configuration.create!(account: account, rules: { automatic_action_daily_limit: 2,
                                                                      portfolio_capacity_limits: [{ user_id: actor.id, maximum: 10, availability: 1,
                                                                                                    dedication: 1 }] })
  end
  let(:book) do
    JrcRelationship::Playbook.create!(account: account, name: 'Private native automatic work', active: true, trigger_kind: 'no_contact',
                                      steps: [{ 'kind' => 'risk', 'title' => 'Observed native risk', 'after_days' => 0 },
                                              { 'kind' => 'action', 'title' => 'Operational follow-up', 'after_days' => 0 },
                                              { 'kind' => 'activity', 'title' => 'Real native Agenda work', 'after_days' => 0 }])
  end
  let(:service) { JrcRelationship::AutomaticPlaybooks.new(context) }
  let(:options) { { playbook_id: book.id, source_key: 'same-real-observation' } }
  let(:events) do
    JrcCrm::AuditEvent.where(account: account, resource_type: assignment.class.name, resource_id: assignment.id)
                      .where("metadata ->> 'action' = ?", described_class::EVENT)
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'reserves the whole new action set, retains risk identification and creates no false execution or partial task on deferral' do
    bands = %w[P0 P1 P2 P3].zip([90, 80, 60, 0]).map { |code, minimum| { 'code' => code, 'minimum' => minimum } }
    configuration.update!(rules: configuration.rules.merge('priority_bands' => bands))
    assignment.actions.create!(account: account, owner: actor, kind: 'health', reason: 'Already counted monitor work',
                               source_key: 'monitor', metadata: { automatic: true })
    2.times { service.run!(assignment, 'no_contact', **options) }
    retention = assignment.actions.where(kind: 'retention').sole
    expect([assignment.actions.count, retention.metadata['automatic'] == true, retention.factors.slice('priority_band', 'priority_band_score')])
      .to eq([2, false, { 'priority_band' => 'P1', 'priority_band_score' => 80 }])
    expect(assignment.actions.where("source_key LIKE 'playbook:%' OR source_key LIKE 'activity:playbook:%'")).to be_empty
    expect(JrcRelationship::RiskCase.where(assignment: assignment).count).to eq(1)
    expect(JrcRelationship::PlaybookExecution.where(assignment: assignment)).to be_empty
    expect(events.count).to eq(1)
    expect(events.sole.to_value).to include('state' => 'deferred', 'reason' => 'account_daily_budget', 'required_actions' => 2)
    expect(described_class.new(context, assignment).last_attempt.keys).not_to include('source_digest', 'remaining', 'account_count')
  end

  it 'retries current native work after the next account day and preserves idempotence and immutable execution history' do
    travel_to(Time.utc(2026, 11, 5, 23, 30)) do
      configuration
      assignment.actions.create!(account: account, owner: actor, kind: 'health', reason: 'Counted today',
                                 source_key: 'today', metadata: { automatic: true })
      service.run!(assignment, 'no_contact', **options)
      expect(Time.iso8601(events.sole.to_value.fetch('eligible_after'))).to eq(Time.utc(2026, 11, 6, 3))
      travel_to(Time.utc(2026, 11, 6, 3))
      service.run!(assignment, 'no_contact', **options)
      execution = JrcRelationship::PlaybookExecution.where(assignment: assignment).sole
      frozen = execution.attributes.deep_dup
      service.run!(assignment, 'no_contact', **options)
      expect(assignment.actions.count).to eq(4)
      expect(assignment.actions.where("metadata ->> 'automatic' = 'true'").count).to eq(3)
      expect(JrcRelationship::PlaybookExecution.where(assignment: assignment).sole.attributes).to eq(frozen)
      expect(assignment.actions.where.not(activity_id: nil).count).to eq(3)
      expect(JrcRelationship::RiskCase.where(assignment: assignment).count).to eq(1)
      expect(events.order(:id).map { |row| row.to_value.fetch('state') }).to eq(%w[deferred admitted])
    end
  end

  it 'leaves explicit manual playbooks outside the automatic ceiling and counts only real new automatic actions' do
    configuration.update!(rules: { automatic_action_daily_limit: 1 })
    JrcRelationship::Playbooks.new(context).run!(assignment, 'no_contact', playbook_id: book.id, source_key: 'manual')
    expect(assignment.actions.count).to eq(3)
    expect(assignment.actions.where("metadata ->> 'automatic' = 'true'")).to be_empty
    expect(events).to be_empty
    expect(JrcRelationship::PlaybookExecution.where(assignment: assignment).count).to eq(1)
  end

  it 'rolls back every newly created task when automatic Agenda allocation fails and keeps native risk work visible' do
    assignment
    configuration.update!(rules: { automatic_action_daily_limit: 2, portfolio_capacity_limits: [
                            { user_id: actor.id, maximum: 10, availability: 0, dedication: 1 }
                          ] })
    service.run!(assignment, 'no_contact', **options)
    expect(assignment.actions.pluck(:kind)).to eq(['retention'])
    expect(JrcRelationship::RiskCase.where(assignment: assignment).count).to eq(1)
    expect(JrcRelationship::PlaybookExecution.where(assignment: assignment)).to be_empty
    expect(events.sole.to_value).to include('state' => 'deferred', 'reason' => 'native_assignment_unavailable')
    2.times { service.run!(assignment, 'no_contact', **options) }
    expect(events.count).to eq(1)
  end

  it 'passes monitoring through automatic admission while retaining its source action and source risks' do
    configuration.update!(rules: { automatic_action_daily_limit: 1 })
    book
    signals = JrcRelationship::CustomerSignals.new(context: context, assignment: assignment).call.merge(days_without_contact: 35)
    assignment.with_lock do
      JrcRelationship::Processor.new(context: context, assignment: assignment).send(:evaluate, signals, configuration.effective_rules)
    end
    expect(events.order(:id).last.to_value).to include('state' => 'deferred', 'reason' => 'account_daily_budget')
    expect(assignment.actions.where("source_key LIKE 'playbook:%'")).to be_empty
    expect(JrcRelationship::PlaybookExecution.where(assignment: assignment)).to be_empty
    expect(assignment.actions.where("metadata ->> 'automatic' = 'true'").count).to eq(1)
  end

  it 'returns the scoped last attempt in the existing customer view without leaking plan identity, foreign records or private portfolios' do
    configuration.update!(rules: { automatic_action_daily_limit: 1 })
    service.run!(assignment, 'no_contact', **options)
    url = "/api/v1/accounts/#{account.id}/relationship/portfolio/#{assignment.id}"
    headers = actor.create_new_auth_token
    get url, headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('automatic_playbook_attempt')).to include('state' => 'deferred', 'required_actions' => 2)
    expect(response.body).not_to include(book.name, 'source_digest', 'same-real-observation')
    analyst = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: %w[contact_manage jrc_relationship_view])
    account.account_users.find_by!(user: analyst).update!(custom_role: role)
    get url, headers: analyst.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    foreign = create(:account)
    get "/api/v1/accounts/#{foreign.id}/relationship/portfolio/#{assignment.id}", headers: headers
    expect(response).to have_http_status(:forbidden)
  end
end

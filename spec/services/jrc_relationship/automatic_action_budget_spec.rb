require 'rails_helper'

RSpec.describe JrcRelationship::AutomaticActionBudget do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: user)) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: user, contact: create(:contact, account: account)) }
  let(:configuration) { JrcRelationship::Configuration.create!(account: account, rules: { automatic_action_daily_limit: 1 }) }
  let(:data) { { health: { score: 30, band: 'critical' }, days_without_contact: 35, _source_ids: {} } }
  let(:processor) { JrcRelationship::Processor.new(context: context, assignment: assignment) }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'rejects malformed reservations before executing any work and admits only an entire explicitly required set' do
    [0, -1, 1.5, '2', false].each do |invalid|
      expect { described_class.new(context: context, assignment: assignment).call(required: invalid) { raise 'Must not execute' } }
        .to raise_error(ArgumentError)
    end
    configuration
    budget = described_class.new(context: context, assignment: assignment)
    expect(budget.call(required: 2) { raise 'A two-task set cannot fit the configured one-task ceiling' }).to be_nil
    expect(budget.next_allowed_at).to be_present
    expect(assignment.actions).to be_empty
  end

  it 'shares the configured daily ceiling across customers without suppressing updates of existing actions or risks' do
    rules = configuration.effective_rules
    action = processor.action!('health', 'Synthetic first cause', data, rules)
    other = JrcRelationship::Assignment.create!(account: account, owner: user, contact: create(:contact, account: account))
    next_processor = JrcRelationship::Processor.new(context: context, assignment: other)
    2.times { expect(next_processor.action!('health', 'Synthetic blocked cause', data, rules)).to be_nil }
    processor.action!('health_drop', 'Synthetic updated cause', data.merge(health: { score: 10, band: 'critical' }), rules)
    next_processor.send(:risk!, 'health', 'Critical evidence remains visible', 'critical', data)
    expect(action.reload.metadata.fetch('related_signals')).to include('health_drop')
    expect(JrcRelationship::RiskCase.where(assignment: other, severity: 'critical').count).to eq(1)
    events = JrcCrm::AuditEvent.where(account: account, resource_id: other.id).where("metadata ->> 'action' = 'automatic_action_suppressed'")
    expect(events.count).to eq(1)
    expect(events.first.to_value.keys).not_to include('count', 'remaining', 'customer_ids')
  end

  it 'uses the account day, keeps completed work in the budget and resets only at the next local midnight' do
    account.update!(reporting_timezone: 'America/Sao_Paulo')
    travel_to(Time.utc(2026, 11, 5, 23, 30)) do
      rules = configuration.effective_rules
      first = processor.action!('health', 'Synthetic today', data, rules)
      fields = { assignment_id: assignment.id, lock_version: first.lock_version, status: 'completed',
                 result: 'Synthetic completed follow-up', customer_confirmation: 'not_applicable' }
      JrcRelationship::Workflow.new(context).save(kind: 'actions', id: first.id, attributes: fields)
      travel_to(Time.utc(2026, 11, 6, 2, 59))
      expect(processor.action!('finance', 'Same local day', data, rules)).to be_nil
      travel_to(Time.utc(2026, 11, 6, 3, 0))
      expect(processor.action!('finance', 'New local day', data, rules)).to be_persisted
    end
  end

  it 'does not count manual actions or another account and leaves the unconfigured legacy behavior unchanged' do
    configuration
    assignment.actions.create!(account: account, kind: 'manual', reason: 'Human follow-up', source_key: 'manual')
    foreign = create(:account)
    foreign_user = create(:user, account: foreign, role: :administrator)
    foreign_assignment = JrcRelationship::Assignment.create!(account: foreign, owner: foreign_user, contact: create(:contact, account: foreign))
    foreign_assignment.actions.create!(account: foreign, kind: 'health', reason: 'Other account', source_key: 'foreign',
                                       metadata: { automatic: true })
    expect(processor.action!('health', 'Current account', data, configuration.effective_rules)).to be_persisted
    configuration.update!(rules: { automatic_action_daily_limit: 0 })
    expect(processor.action!('finance', 'Disabled configured ceiling', data, configuration.effective_rules)).to be_persisted
  end

  it 'rejects fractional or negative limits and prevents a unit policy from overriding the global ceiling' do
    [-1, 1.5, '3', false].each do |value|
      expect(JrcRelationship::Configuration.new(account: account, rules: { automatic_action_daily_limit: value })).not_to be_valid
    end
    team = create(:team, account: account)
    expect(JrcRelationship::Configuration.new(account: account, scope_key: "team:#{team.id}",
                                              rules: { automatic_action_daily_limit: 3 })).not_to be_valid
  end

  it 'refuses an assignment outside the authenticated scope before calling the creation block' do
    other = create(:account)
    foreign = JrcRelationship::Assignment.create!(account: other, contact: create(:contact, account: other))
    expect { described_class.new(context: context, assignment: foreign).call { raise 'Must not be called' } }
      .to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'keeps the account ceiling mandatory when the customer has its own monitoring configuration' do
    processor.action!('health', 'First account slot', data, configuration.effective_rules)
    company = account.master_companies.create!(name: 'Synthetic customer with its own settings')
    other = JrcRelationship::Assignment.create!(account: account, company: company, owner: user)
    JrcRelationship::Configuration.create!(account: account, scope_key: "company:#{company.id}", rules: { sla_hours: 36 })
    fresh = JrcRelationship::Context.new(context.member)
    scoped_rules = fresh.configuration(other).effective_rules
    expect(scoped_rules.fetch('automatic_action_daily_limit')).to eq(0)
    expect(JrcRelationship::Processor.new(context: fresh, assignment: other).action!('health', 'Scoped cause', data, scoped_rules)).to be_nil
    expect(other.actions).to be_empty
  end
end

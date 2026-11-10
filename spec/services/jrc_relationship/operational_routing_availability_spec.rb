require 'rails_helper'

RSpec.describe JrcRelationship::OperationalRouting do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:owner) { create(:user, account: account, role: :administrator) }
  let(:substitute) { create(:user, account: account, role: :administrator) }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: actor)) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: owner, contact: create(:contact, account: account)) }
  let(:action) do
    assignment.actions.build(account: account, kind: 'health', reason: 'Synthetic critical routing', priority: 95, source_key: SecureRandom.uuid)
  end
  let(:limits) do
    [owner, substitute].map { |user| { 'user_id' => user.id, 'maximum' => 10, 'availability' => 1, 'dedication' => 1 } }
  end
  let(:configuration) { JrcRelationship::Configuration.create!(account: account, rules: { portfolio_capacity_limits: limits }) }
  let(:queue) do
    JrcOperations::Queue.create!(account: account, name: 'Synthetic routing availability', code: 'SYNTHETIC-CS-AVAILABLE',
                                 assignment_strategy: 'round_robin', settings: { scopes: ['relationship'], user_ids: [owner.id, substitute.id] })
  end

  before do
    account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    actor
  end

  it 'uses the existing owner and preserves legacy routing when no availability is configured' do
    described_class.new(context).prepare!(action)
    action.save!
    expect(action.reload.owner_id).to eq(owner.id)
    expect(action.operations_queue.code).to eq('RELATIONSHIP-GERAL')
    expect(action.metadata).not_to have_key('routing_waiting_reason')
  end

  it 'routes to an authorized substitute when the owner has zero availability, retaining allocation and membership history' do
    assignment
    limits.first['availability'] = 0
    configuration
    queue
    before = [assignment.owner_id, AccountUser.where(account: account).count]
    described_class.new(context).prepare!(action)
    action.save!
    expect(action.reload.owner_id).to eq(substitute.id)
    expect([assignment.reload.owner_id, AccountUser.where(account: account).count]).to eq(before)
    expect(action.priority).to eq(95)
  end

  it 'keeps an unassigned critical item visible in its real queue with SLA when no eligible analyst is available' do
    assignment
    limits.each { |entry| entry['dedication'] = 0 }
    configuration
    queue
    described_class.new(context).prepare!(action)
    action.save!
    expect(action.reload.owner_id).to be_nil
    expect(action.metadata).to include('routing_waiting_reason' => 'no_authorized_available_analyst')
    expect([action.operations_queue_id, action.operations_sla_policy_id, action.sla_due_at]).to all(be_present)
    expect(context.records(JrcRelationship::Action)).to exist(id: action.id)
    expect(action.priority).to eq(95)
  end

  it 'does not let a more specific policy disable the account availability constraint' do
    team = create(:team, account: account)
    assignment.update!(team: team)
    limits.first['availability'] = 0
    configuration
    local_limits = limits.map { |entry| entry.merge('availability' => 1) }
    JrcRelationship::Configuration.create!(account: account, scope_key: "team:#{team.id}", rules: { portfolio_capacity_limits: local_limits })
    queue
    described_class.new(context).prepare!(action)
    action.save!
    expect(action.reload.owner_id).to eq(substitute.id)
  end

  it 'does not select an otherwise available substitute outside the native operating unit scope' do
    company = account.master_companies.create!(name: 'Synthetic routing operator', relationship_type: 'internal', tax_id: '11444777000161')
    units = Array.new(2) do |index|
      account.jrc_crm_business_units.create!(name: "Synthetic routing unit #{index}", code: SecureRandom.hex(6), company_id: company.id)
    end
    assignment.update!(business_unit: units.first)
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: company,
                                                business_unit: units.first, active: true, structure_managed: true)
    account.jrc_crm_user_business_units.create!(user: substitute, scope: 'BUSINESS_UNIT', company: company,
                                                business_unit: units.last, active: true, structure_managed: true)
    limits.first['availability'] = 0
    configuration
    queue
    described_class.new(context).prepare!(action)
    action.save!
    expect(action.reload.owner_id).to be_nil
    expect(action.metadata).to include('routing_waiting_reason' => 'no_authorized_available_analyst')
  end

  it 'preserves an explicitly selected native manual owner even when automatic routing would defer them' do
    assignment
    limits.first['availability'] = 0
    configuration
    queue
    action.owner = owner
    described_class.new(context).prepare!(action, preserve_owner: true)
    action.save!
    expect(action.reload.owner_id).to eq(owner.id)
    expect(action.metadata).not_to have_key('routing_waiting_reason')
  end
end

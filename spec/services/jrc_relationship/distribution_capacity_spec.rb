require 'rails_helper'

RSpec.describe JrcRelationship::DistributionCapacity do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:target) { create(:user, account: account, role: :agent) }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: actor)) }
  let(:first) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:second) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:configuration) do
    JrcRelationship::Configuration.create!(account: account, rules: { portfolio_capacity_limits: [
                                             { user_id: actor.id, maximum: 100, availability: 1, dedication: 1 },
                                             { user_id: target.id, maximum: 2, availability: 1, dedication: 1 }
                                           ] })
  end
  let(:service) { JrcRelationship::ReviewedPortfolioBatch.new(context) }
  let(:inputs) { { 'ids' => [first.id, second.id], 'operation' => 'assign', 'owner_id' => target.id, 'request_id' => SecureRandom.uuid } }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'uses configured customer capacity and stable reviewed before/final facts across its own individual receipts' do
    configuration
    preview = service.preview(inputs)
    before = preview.fetch('capacity').first
    expect(before).to include('current' => 0, 'incoming' => 2, 'projected' => 2, 'effective_capacity' => 2, 'blocker' => nil)
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    service.advance(preview.fetch('id'), limit: 1)
    expect(service.advance(preview.fetch('id')).fetch('state')).to eq('completed')
    expect([first.reload.owner_id, second.reload.owner_id]).to eq([target.id, target.id])
  end

  it 'keeps an over-capacity simulation read-only and blocks confirmation before any transfer' do
    configuration.update!(rules: configuration.rules.deep_merge('portfolio_capacity_limits' => [
                                                                  { 'user_id' => actor.id, 'maximum' => 100, 'availability' => 1, 'dedication' => 1 },
                                                                  { 'user_id' => target.id, 'maximum' => 1, 'availability' => 1, 'dedication' => 1 }
                                                                ]))
    preview = service.preview(inputs)
    expect(preview.fetch('capacity').first).to include('blocker' => 'capacity_exceeded', 'available_after' => -1)
    expect { service.approve(preview.fetch('id'), digest: preview.fetch('digest')) }.to raise_error(ArgumentError, /capacity/)
    expect([first.reload.owner_id, second.reload.owner_id]).to eq([actor.id, actor.id])
  end

  it 'computes effective capacity from availability and dedication without inventing a fixed customer limit' do
    entry = { 'maximum' => 10, 'availability' => 0.8, 'dedication' => 0.5 }
    expect(JrcRelationship::DistributionCapacityPolicy.effective(entry)).to eq(4)
    expect(JrcRelationship::DistributionCapacityPolicy.effective(entry.merge('availability' => 0))).to eq(0)
  end

  it 'protects native individual writes outside the batch API and retains the original owner on failure' do
    configuration.update!(rules: configuration.rules.deep_merge('portfolio_capacity_limits' => [
                                                                  { 'user_id' => actor.id, 'maximum' => 100, 'availability' => 1, 'dedication' => 1 },
                                                                  { 'user_id' => target.id, 'maximum' => 0, 'availability' => 1, 'dedication' => 1 }
                                                                ]))
    expect { first.update!(owner: target) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(first.errors.full_messages.join).to include('exceeds the configured portfolio capacity')
    expect(first.reload.owner_id).to eq(actor.id)
  end

  it 'invalidates the old simulation when another allocation changes the destination workload' do
    configuration
    preview = service.preview(inputs)
    JrcRelationship::Assignment.create!(account: account, owner: target, contact: create(:contact, account: account))
    expect { service.approve(preview.fetch('id'), digest: preview.fetch('digest')) }.to raise_error(ArgumentError, /capacity changed/)
    expect(first.reload.owner_id).to eq(actor.id)
  end

  it 'includes clients without an owner as incoming allocations' do
    configuration
    first.update!(owner: nil)
    preview = service.preview(inputs)
    expect(preview.fetch('capacity').first).to include('incoming' => 2, 'projected' => 2)
  end

  it 'does not treat an already-owned no-op item as another incoming allocation' do
    configuration
    first.update!(owner: target)
    preview = service.preview(inputs)
    expect(preview.fetch('capacity').first).to include('current' => 1, 'incoming' => 1, 'projected' => 2)
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    expect(service.advance(preview.fetch('id')).fetch('state')).to eq('completed')
  end

  it 'rejects cross-account users, duplicate limits and invalid percentages in persisted configuration' do
    limits = [{ 'user_id' => target.id, 'maximum' => 2, 'availability' => 1, 'dedication' => 1 }]
    expect { JrcRelationship::DistributionCapacityPolicy.validate!(account, limits * 2) }.to raise_error(ArgumentError)
    expect do
      JrcRelationship::DistributionCapacityPolicy.validate!(account, [limits.first.merge('availability' => 1.1)])
    end.to raise_error(ArgumentError)
    foreign = create(:user, account: create(:account))
    expect do
      JrcRelationship::DistributionCapacityPolicy.validate!(account, [limits.first.merge('user_id' => foreign.id)])
    end.to raise_error(ArgumentError)
  end

  it 'blocks reactivation at a full destination and permits edits which add no workload' do
    configuration
    first.update!(owner: target)
    second.update!(owner: target)
    inactive = JrcRelationship::Assignment.create!(account: account, owner: target, status: 'inactive', contact: create(:contact, account: account))
    expect { inactive.update!(status: 'active') }.to raise_error(ActiveRecord::RecordInvalid)
    expect { first.update!(settings: { complexity: 'changed without added workload' }) }.not_to raise_error
    expect(inactive.reload.status).to eq('inactive')
  end

  it 'retains an eligible handoff unassigned when the configured destination is unavailable, idempotently' do
    configuration.update!(rules: configuration.rules.deep_merge('portfolio_capacity_limits' => [
                                                                  { 'user_id' => target.id, 'maximum' => 0, 'availability' => 1, 'dedication' => 1 }
                                                                ]))
    identity = { contact_id: create(:contact, account: account).id }
    attributes = { owner_id: target.id, status: 'active' }
    assignment = JrcRelationship::HandoffAllocation.call(account: account, identity: identity, attributes: attributes)
    expect(assignment.owner_id).to be_nil
    expect(assignment.settings).to include('allocation_pending_reason' => 'capacity_unavailable')
    expect(JrcRelationship::HandoffAllocation.call(account: account, identity: identity, attributes: attributes).id).to eq(assignment.id)
  end

  it 'does not mask an unrelated invalid handoff identity as capacity refusal' do
    configuration
    expect do
      JrcRelationship::HandoffAllocation.call(account: account, identity: {}, attributes: { owner_id: target.id, status: 'active' })
    end.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'prevents classification changes from removing a hard native team scope' do
    team = create(:team, account: account)
    first.update!(team: team)
    JrcRelationship::Configuration.create!(account: account, scope_key: "team:#{team.id}", rules: { portfolio_transfer_approval_required: true })
    params = ActionController::Parameters.new(team_id: nil).permit(:team_id)
    expect { JrcRelationship::DistributionScopeGuard.check!(context, first, params) }.to raise_error(ArgumentError, /governed scope/)
    expect(first.reload.team_id).to eq(team.id)
  end

  it 'redacts captured workload when the reader cannot see the whole destination portfolio' do
    visible_team = create(:team, account: account)
    hidden_team = create(:team, account: account)
    viewer = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account,
                                permissions: %w[contact_manage jrc_crm jrc_relationship_view jrc_relationship_team])
    account.account_users.find_by!(user: viewer).update!(custom_role: role)
    TeamMember.create!(team: visible_team, user: viewer)
    first.update!(team: visible_team)
    second.update!(team: visible_team)
    JrcRelationship::Assignment.create!(account: account, owner: target, team: hidden_team, contact: create(:contact, account: account))
    configuration
    preview = service.preview(inputs)
    review = JrcRelationship::BatchReview.find(preview.fetch('id'))
    reader = JrcRelationship::Context.new(account.account_users.find_by!(user: viewer))
    expect(reader.assignments.where(id: [first.id, second.id]).count).to eq(2)
    expect(described_class.new(reader).for_view(review)).to eq([
                                                                 { 'scope_key' => 'account', 'user_id' => target.id,
                                                                   'unit' => 'customers', 'blocker' => 'capacity_scope_denied' }
                                                               ])
    expect { described_class.new(reader).verify!(review) }.to raise_error(Pundit::NotAuthorizedError)
  end
end

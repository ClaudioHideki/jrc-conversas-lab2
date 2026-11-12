require 'rails_helper'

RSpec.describe JrcRelationship::ResponsibilityTransfer do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :agent) }
  let(:target) { create(:user, account: account, role: :agent) }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: actor)) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:service) { JrcRelationship::ReviewedPortfolioBatch.new(context) }
  let(:second_assignment) do
    JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account))
  end
  let(:inputs) do
    { ids: [assignment.id, second_assignment.id], operation: 'assign', owner_id: target.id, request_id: SecureRandom.uuid,
      transfer_responsibilities: true, justification: 'Synthetic private justification' }
  end

  before do
    account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    role = account.custom_roles.create!(name: 'Synthetic scoped supervisor',
                                        permissions: %w[contact_manage jrc_crm jrc_relationship_view jrc_relationship_manage jrc_relationship_team])
    account.account_users.find_by!(user: actor).update!(custom_role: role)
    team = create(:team, account: account)
    team.team_members.create!(user: actor)
    team.team_members.create!(user: target)
  end

  it 'completes supported work before losing the old owner scope, preserving the frozen proposal and effective receipt' do
    action = assignment.actions.create!(account: account, owner: actor, kind: 'manual', reason: 'Synthetic scoped commitment',
                                        source_key: SecureRandom.uuid, due_at: 2.days.from_now)
    activity = JrcRelationship::Workflow.new(context).project_action!(action)
    preview = service.preview(ids: [assignment.id], operation: 'assign', owner_id: target.id, request_id: SecureRandom.uuid,
                              transfer_responsibilities: true, justification: 'Synthetic scoped complete handoff')
    review = JrcRelationship::BatchReview.find(preview.fetch('id'))
    original = review.attributes.slice('snapshot', 'digest')
    service.approve(review.id, digest: preview.fetch('digest'))
    result = service.advance(review.id)
    expect(result.fetch('state')).to eq('completed')
    expect([assignment.reload.owner_id, action.reload.owner_id, activity.reload.user_id]).to eq([target.id, target.id, target.id])
    expect(JrcRelationship::Context.new(context.member).assignments.exists?(id: assignment.id)).to be(false)
    destination = JrcRelationship::Context.new(account.account_users.find_by!(user: target))
    expect(destination.records(JrcRelationship::Action).exists?(id: action.id)).to be(true)
    expect(review.reload.attributes.slice('snapshot', 'digest')).to eq(original)
    expect(review.items.first.state).to eq('applied')
    expect(review.items.first.receipt.fetch('resources').first).to include('owner_id' => target.id)
  end

  it 'continues a partial owner-scoped transfer using only its own receipts and preserves captured capacity' do
    JrcRelationship::Configuration.create!(account: account, rules: { portfolio_capacity_limits: [
                                             { user_id: actor.id, maximum: 2, availability: 1, dedication: 1 },
                                             { user_id: target.id, maximum: 2, availability: 1, dedication: 1 }
                                           ] })
    preview = service.preview(inputs)
    review = JrcRelationship::BatchReview.find(preview.fetch('id'))
    original = review.attributes.slice('snapshot', 'digest')
    service.approve(review.id, digest: preview.fetch('digest'))
    partial = service.advance(review.id, limit: 1)
    expect(partial).to include('state' => 'running', 'source_access_limited' => true, 'summary' => nil, 'capacity' => [])
    expect(partial.fetch('inputs')).not_to have_key('justification')
    expect(partial.fetch('items').pluck('label')).to eq([nil, nil])
    expect(service.advance(review.id).fetch('state')).to eq('completed')
    expect([assignment.reload.owner_id, second_assignment.reload.owner_id]).to eq([target.id, target.id])
    expect(review.reload.attributes.slice('snapshot', 'digest')).to eq(original)
    expect { JrcRelationship::Context.new(context.member).assignment(assignment.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'cancels the remaining work after a scoped partial handoff without undoing the applied receipt' do
    preview = service.preview(inputs)
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    service.advance(preview.fetch('id'), limit: 1)
    result = service.cancel(preview.fetch('id'))
    expect(result).to include('state' => 'canceled', 'source_access_limited' => true)
    expect(result.fetch('items').pluck('state')).to eq(%w[applied canceled])
    expect([assignment.reload.owner_id, second_assignment.reload.owner_id]).to eq([target.id, actor.id])
  end

  it 'denies further execution and receipt access when the original actor loses team permission' do
    preview = service.preview(inputs)
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    service.advance(preview.fetch('id'), limit: 1)
    role = account.account_users.find_by!(user: actor).custom_role
    role.update!(permissions: %w[contact_manage jrc_relationship_view jrc_relationship_manage])
    expect { service.advance(preview.fetch('id')) }.to raise_error(Pundit::NotAuthorizedError)
    expect { service.get(preview.fetch('id')) }.to raise_error(Pundit::NotAuthorizedError)
    expect(second_assignment.reload.owner_id).to eq(actor.id)
  end

  it 'rejects a changed destination grant after one applied receipt without transferring the remaining customer' do
    preview = service.preview(inputs)
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    service.advance(preview.fetch('id'), limit: 1)
    role = account.custom_roles.create!(name: 'Synthetic destination read only', permissions: %w[jrc_relationship_view])
    account.account_users.find_by!(user: target).update!(custom_role: role)
    expect { service.advance(preview.fetch('id')) }.to raise_error(Pundit::NotAuthorizedError)
    expect(service.get(preview.fetch('id'))).to include('source_access_limited' => true, 'state' => 'running')
    expect(second_assignment.reload.owner_id).to eq(actor.id)
  end

  it 'does not extend capacity visibility to unrelated destination-owned customers' do
    JrcRelationship::Configuration.create!(account: account, rules: { portfolio_capacity_limits: [
                                             { user_id: actor.id, maximum: 3, availability: 1, dedication: 1 },
                                             { user_id: target.id, maximum: 3, availability: 1, dedication: 1 }
                                           ] })
    preview = service.preview(inputs)
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    service.advance(preview.fetch('id'), limit: 1)
    JrcRelationship::Assignment.create!(account: account, owner: target, contact: create(:contact, account: account))
    expect { service.advance(preview.fetch('id')) }.to raise_error(Pundit::NotAuthorizedError)
    expect(second_assignment.reload.owner_id).to eq(actor.id)
    expect(service.get(preview.fetch('id')).fetch('capacity')).to eq([])
  end

  it 'does not expose an actor-owned execution receipt to another user or account' do
    preview = service.preview(inputs)
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    service.advance(preview.fetch('id'), limit: 1)
    target_context = JrcRelationship::Context.new(account.account_users.find_by!(user: target))
    foreign = create(:account)
    foreign_actor = create(:user, account: foreign, role: :administrator)
    foreign.enable_features!('jrc_customer_master', 'jrc_relationship')
    foreign_context = JrcRelationship::Context.new(foreign.account_users.find_by!(user: foreign_actor))
    expect { JrcRelationship::ReviewedPortfolioBatch.new(target_context).get(preview.fetch('id')) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { JrcRelationship::ReviewedPortfolioBatch.new(foreign_context).get(preview.fetch('id')) }.to raise_error(ActiveRecord::RecordNotFound)
  end
end

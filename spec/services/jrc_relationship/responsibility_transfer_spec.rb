require 'rails_helper'

RSpec.describe JrcRelationship::ResponsibilityTransfer do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:target) { create(:user, account: account, role: :administrator) }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: actor)) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:service) { JrcRelationship::ReviewedPortfolioBatch.new(context) }
  let(:inputs) do
    { 'ids' => [assignment.id], 'operation' => 'assign', 'owner_id' => target.id, 'transfer_responsibilities' => true,
      'justification' => 'Synthetic complete responsibility handoff', 'request_id' => SecureRandom.uuid }
  end
  let(:action) do
    JrcRelationship::Action.create!(account: account, assignment: assignment, owner: actor, kind: 'health', reason: 'Synthetic follow-up',
                                    source_key: 'synthetic-pending-action', due_at: 1.day.from_now)
  end
  let(:plan) { JrcRelationship::SuccessPlan.create!(account: account, assignment: assignment, owner: actor, title: 'Synthetic success plan') }
  let(:meeting) do
    JrcRelationship::Qbr.create!(account: account, assignment: assignment, owner: actor, title: 'Synthetic QBR', scheduled_at: 1.day.from_now)
  end
  let(:risk) do
    JrcRelationship::RiskCase.create!(account: account, assignment: assignment, owner: actor, reason: 'Synthetic open risk', severity: 'high',
                                      source_key: 'synthetic-open-risk')
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'freezes every pending CS destination without mutations, then atomically moves supported responsibilities and agenda' do
    pending = [action, plan, meeting, risk]
    activity = JrcRelationship::Workflow.new(context).project_action!(action)
    completed = assignment.actions.create!(account: account, owner: actor, kind: 'manual', reason: 'Historical completed action',
                                           source_key: 'history', status: 'completed', completed_at: Time.current,
                                           completed_by: actor, result: 'Historical result')
    original = completed.attributes.deep_dup
    preview = service.preview(inputs)
    captured = JrcRelationship::BatchReview.find(preview.fetch('id')).snapshot.deep_dup
    expect(preview.fetch('responsibilities').first.fetch('entries').pluck('kind')).to contain_exactly('actions', 'plans', 'qbrs', 'risks',
                                                                                                      'activities')
    expect([assignment.reload.owner_id, *pending.map { |row| row.reload.owner_id }, activity.reload.user_id]).to all(eq(actor.id))
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    expect(assignment.reload.owner_id).to eq(actor.id)
    result = service.advance(preview.fetch('id'))
    expect(result).to include('state' => 'completed', 'responsibilities' => [include('state' => 'executed')])
    expect([assignment.reload.owner_id, *pending.map { |row| row.reload.owner_id }, activity.reload.user_id]).to all(eq(target.id))
    expect(completed.reload.attributes).to eq(original)
    expect([JrcRelationship::BatchReview.find(preview.fetch('id')).snapshot, service.advance(preview.fetch('id'))]).to eq([captured, result])
  end

  it 'invalidates a changed pending responsibility before confirmation without changing the immutable proposal' do
    plan
    preview = service.preview(inputs)
    original = JrcRelationship::BatchReview.find(preview.fetch('id')).snapshot.deep_dup
    plan.update!(title: 'Changed after simulation')
    expect { service.approve(preview.fetch('id'), digest: preview.fetch('digest')) }.to raise_error(ArgumentError, /responsibilities changed/)
    expect(service.get(preview.fetch('id')).fetch('responsibilities').first.fetch('state')).to eq('stale')
    expect(assignment.reload.owner_id).to eq(actor.id)
    expect(JrcRelationship::BatchReview.find(preview.fetch('id')).snapshot).to eq(original)
  end

  it 'detects a newly created pending responsibility after confirmation and never reports its failed item as executed' do
    action
    preview = service.preview(inputs)
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    plan
    result = service.advance(preview.fetch('id'))
    expect(result.fetch('state')).to eq('attention')
    expect(result.fetch('responsibilities').first.fetch('state')).to eq('failed')
    expect([assignment.reload.owner_id, action.reload.owner_id, plan.reload.owner_id]).to all(eq(actor.id))
  end

  it 'requires a reviewed proposal, an actual destination, a justification and a literal boolean option' do
    expect { service.preview(inputs.merge('owner_id' => nil)) }.to raise_error(ArgumentError, /destination/)
    expect { service.preview(inputs.merge('justification' => nil)) }.to raise_error(ArgumentError)
    expect { service.preview(inputs.merge('transfer_responsibilities' => 'true')) }.to raise_error(ArgumentError)
    expect do
      JrcRelationship::PortfolioBatch.new(context, ActionController::Parameters.new(inputs)).call
    end.to raise_error(ArgumentError, /reviewed proposal/)
    expect(assignment.reload.owner_id).to eq(actor.id)
  end

  it 'keeps responsibility and allocation pending when a linked project requires its native transfer' do
    account.enable_features!('jrc_projects')
    project = JrcProjects::Projects::Create.call(account: account, actor: actor, attributes: { name: 'Synthetic linked project' },
                                                 idempotency_key: SecureRandom.uuid)
    plan.update!(project: project)
    preview = service.preview(inputs)
    expect(preview.fetch('responsibilities').first).to include('state' => 'blocked')
    expect { service.approve(preview.fetch('id'), digest: preview.fetch('digest')) }.to raise_error(ArgumentError, /native source review/)
    expect(assignment.reload.owner_id).to eq(actor.id)
  end

  it 'cancels a proposal without falsely showing its responsibilities as transferred' do
    action
    preview = service.preview(inputs)
    result = service.cancel(preview.fetch('id'))
    expect(result.fetch('responsibilities').first.fetch('state')).to eq('canceled')
    expect(action.reload.owner_id).to eq(actor.id)
  end

  it 'rolls back the whole customer when the destination loses native contract visibility before execution' do
    target_member = account.account_users.find_by!(user: target)
    target_member.update!(role: :agent)
    order = account.jrc_crm_sales_orders.create!(owner: target, contact: assignment.contact, status: 'completed')
    contract = account.jrc_crm_contracts.create!(sales_order: order, owner: target, contact: assignment.contact)
    renewal = JrcRelationship::Renewal.create!(account: account, assignment: assignment, owner: actor, contract: contract,
                                               renewal_on: 30.days.from_now.to_date)
    action
    plan
    preview = service.preview(inputs)
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    contract.update!(owner: actor)
    expect { service.advance(preview.fetch('id')) }.to raise_error(Pundit::NotAuthorizedError)
    expect([assignment.reload.owner_id, action.reload.owner_id, plan.reload.owner_id, renewal.reload.owner_id]).to all(eq(actor.id))
    review = JrcRelationship::BatchReview.find(preview.fetch('id'))
    expect(review.items.pluck(:state)).to eq(['pending'])
    expect(review.state).to eq('running')
  end

  it 'blocks transfer of an agenda activity shared with another active success plan' do
    activity = JrcRelationship::Workflow.new(context).project_action!(action)
    other = JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account))
    JrcRelationship::SuccessPlan.create!(account: account, assignment: other, owner: actor, title: 'Shared source',
                                         goals: [{ 'metric' => 'Synthetic shared agenda', 'activity_id' => activity.id }])
    preview = service.preview(inputs)
    expect(preview.fetch('responsibilities').first.fetch('blockers')).to include('shared_activity_requires_native_review')
    expect { service.approve(preview.fetch('id'), digest: preview.fetch('digest')) }.to raise_error(ArgumentError, /native source review/)
    expect(activity.reload.user_id).to eq(actor.id)
  end

  it 'does not expose responsibility details from another account' do
    action
    preview = service.preview(inputs)
    foreign = create(:account)
    foreign.enable_features!('jrc_customer_master', 'jrc_relationship')
    user = create(:user, account: foreign, role: :administrator)
    reader = JrcRelationship::Context.new(foreign.account_users.find_by!(user: user))
    data = JrcRelationship::ResponsibilityReview.new(reader).for_view(JrcRelationship::BatchReview.find(preview.fetch('id')))
    expect(data.first).to include('state' => 'unavailable', 'entries' => [])
    expect(data.to_json).not_to include(action.reason, assignment.label)
  end

  it 'uses the reviewed customer name on every responsibility comparison without rewriting its source snapshot' do
    action
    preview = service.preview(inputs)
    original_label = assignment.label
    assignment.contact.update!(name: 'Customer renamed after proposal')
    projection = service.get(preview.fetch('id'))
    expect(projection.fetch('responsibilities').first.fetch('label')).to eq(original_label)
  end
end

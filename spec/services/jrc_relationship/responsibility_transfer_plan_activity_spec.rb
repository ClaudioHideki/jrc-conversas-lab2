require 'rails_helper'

RSpec.describe JrcRelationship::ResponsibilityTransfer do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:target) { create(:user, account: account, role: :administrator) }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: actor)) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:lead) { account.jrc_crm_leads.create!(owner: actor, contact: assignment.contact, name: 'Synthetic plan origin') }
  let(:activity) do
    account.jrc_crm_activities.create!(user: actor, lead: lead, contact: assignment.contact,
                                       title: 'Synthetic plan commitment', activity_type: 'task')
  end
  let(:plan) do
    JrcRelationship::SuccessPlan.create!(account: account, assignment: assignment, owner: actor, title: 'Synthetic plan',
                                         goals: [{ 'metric' => 'Synthetic delivery', 'activity_id' => activity.id }])
  end
  let(:service) { JrcRelationship::ReviewedPortfolioBatch.new(context) }
  let(:inputs) do
    { 'ids' => [assignment.id], 'operation' => 'assign', 'owner_id' => target.id, 'transfer_responsibilities' => true,
      'justification' => 'Synthetic exclusive plan commitment transfer', 'request_id' => SecureRandom.uuid }
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'reviews and transfers the real CRM commitment atomically without rewriting its immutable review or origin' do
    plan
    origin = activity.attributes.slice('lead_id', 'contact_id', 'metadata')
    preview = service.preview(inputs)
    snapshot = JrcRelationship::BatchReview.find(preview.fetch('id')).snapshot.deep_dup
    expect(preview.fetch('responsibilities').first.fetch('entries').pluck('kind')).to contain_exactly('plans', 'activities')
    expect([assignment.reload.owner_id, plan.reload.owner_id, activity.reload.user_id]).to all(eq(actor.id))
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    expect(service.advance(preview.fetch('id')).fetch('state')).to eq('completed')
    expect([assignment.reload.owner_id, plan.reload.owner_id, activity.reload.user_id]).to all(eq(target.id))
    expect(activity.attributes.slice('lead_id', 'contact_id', 'metadata')).to eq(origin)
    expect(JrcRelationship::BatchReview.find(preview.fetch('id')).snapshot).to eq(snapshot)
  end

  it 'blocks an activity shared with a different active plan, retaining every owner' do
    plan
    other = JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account))
    JrcRelationship::SuccessPlan.create!(account: account, assignment: other, owner: actor, title: 'Synthetic shared commitment',
                                         goals: [{ 'metric' => 'Shared reference', 'activity_id' => activity.id }])
    preview = service.preview(inputs)
    expect(preview.fetch('responsibilities').first.fetch('blockers')).to include('shared_activity_requires_native_review')
    expect { service.approve(preview.fetch('id'), digest: preview.fetch('digest')) }.to raise_error(ArgumentError, /native source review/)
    expect([assignment.reload.owner_id, plan.reload.owner_id, activity.reload.user_id]).to all(eq(actor.id))
  end

  it 'blocks another customer origin even when a visible plan references it' do
    plan
    activity.update!(contact: create(:contact, account: account), lead: account.jrc_crm_leads.create!(owner: actor, name: 'Other customer lead'))
    preview = service.preview(inputs)
    expect(preview.fetch('responsibilities').first.fetch('blockers')).to include('activity_origin_requires_native_review')
    expect { service.approve(preview.fetch('id'), digest: preview.fetch('digest')) }.to raise_error(ArgumentError, /native source review/)
    expect(activity.reload.user_id).to eq(actor.id)
  end

  it 'rejects foreign-account and missing references instead of silently omitting their work' do
    plan
    foreign = create(:account)
    foreign_actor = create(:user, account: foreign, role: :administrator)
    foreign_lead = foreign.jrc_crm_leads.create!(owner: foreign_actor, name: 'Synthetic foreign origin')
    foreign_activity = foreign.jrc_crm_activities.create!(user: foreign_actor, lead: foreign_lead,
                                                          title: 'Synthetic foreign commitment', activity_type: 'task')
    plan.update!(goals: [{ 'metric' => 'Foreign reference', 'activity_id' => foreign_activity.id }])
    expect { service.preview(inputs) }.to raise_error(Pundit::NotAuthorizedError)
    plan.update!(goals: [{ 'metric' => 'Missing reference', 'activity_id' => JrcCrm::Activity.maximum(:id) + 1 }])
    expect { service.preview(inputs) }.to raise_error(Pundit::NotAuthorizedError)
    expect(assignment.reload.owner_id).to eq(actor.id)
  end

  it 'invalidates a changed native activity after review and preserves closed history' do
    plan
    preview = service.preview(inputs)
    activity.update!(status: 'completed', completed_at: Time.current)
    expect { service.approve(preview.fetch('id'), digest: preview.fetch('digest')) }.to raise_error(ArgumentError, /responsibilities changed/)
    fresh = service.preview(inputs.merge('request_id' => SecureRandom.uuid))
    service.approve(fresh.fetch('id'), digest: fresh.fetch('digest'))
    expect(service.advance(fresh.fetch('id')).fetch('state')).to eq('completed')
    expect(activity.reload.user_id).to eq(actor.id)
  end
end

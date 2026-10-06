require 'rails_helper'

RSpec.describe 'Relationship functional review' do
  include_context 'JRC Service Desk domain'
  let(:company) { sd_account.master_companies.create!(name: 'Controlled CS test customer') }
  let(:context) { JrcRelationship::Context.new(sd_account_user) }
  let(:workflow) { JrcRelationship::Workflow.new(context) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: sd_account, company: company, owner: sd_user, status: 'active') }
  let(:order) do
    JrcCrm::SalesOrder.create!(account: sd_account, owner: sd_user, contact: sd_contact, source_type: 'manual',
      order_origin: 'direct_sale', status: 'completed', monthly_cents: 0)
  end
  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm', 'jrc_projects')
    sd_contact.update!(master_company: company)
  end

  it 'REL-01 diagnoses existing eligible orders without writing, then backfills once' do
    order
    before = [sd_account.contacts.count, sd_account.master_companies.count, sd_account.jrc_crm_sales_orders.count]
    report = JrcRelationship::Backfill.new(context: context).call
    expect(report).to include(applied: false, eligible: 1, created: 0)
    expect(JrcRelationship::Assignment.where(account: sd_account)).not_to exist
    first = JrcRelationship::Backfill.new(context: context).call(apply: true)
    second = JrcRelationship::Backfill.new(context: context).call(apply: true)
    expect(first[:created]).to eq(1)
    expect(second).to include(created: 0, existing: 1)
    expect(JrcRelationship::Assignment.where(account: sd_account, company: company).count).to eq(1)
    expect(JrcRelationship::Action.where(account: sd_account, source_key: 'handoff').count).to eq(1)
    expect([sd_account.contacts.count, sd_account.master_companies.count, sd_account.jrc_crm_sales_orders.count]).to eq(before)
  end

  it 'REL-01 does not enroll a customer without go-live or required signature' do
    pending = JrcCrm::SalesOrder.create!(account: sd_account, owner: sd_user, contact: sd_contact, source_type: 'manual',
      order_origin: 'direct_sale', status: 'approved', monthly_cents: 0)
    expect(JrcRelationship::Eligibility.new(pending).reason).to eq('go_live_pending')
    order.update!(monthly_cents: 100_000)
    expect(JrcRelationship::Eligibility.new(order).reason).to eq('signature_pending')
    expect(JrcRelationship::Backfill.new(context: context).call(apply: true)[:created]).to eq(0)
  end

  it 'REL-01 resolves the completed native implementation project to its original order' do
    order
    project = JrcProjects::Project.create!(account: sd_account, owner: sd_user, contact: sd_contact, key: 'CSLIVE',
      name: 'Controlled implementation', status: 'active', visibility: 'account', idempotency_key: "crm-order-implementation-#{order.id}")
    expect(JrcRelationship::Eligibility.new(order).reason).to eq('implementation_pending')
    project.update!(status: 'completed')
    first = JrcRelationship::Handoff.call(project)
    second = JrcRelationship::Handoff.call(project)
    expect(second.id).to eq(first.id)
    expect(first.company).to eq(company)
    expect(first.actions.where(source_key: 'handoff').count).to eq(1)
  end

  it 'REL-01 honors disabled automatic handoff even during controlled backfill' do
    order
    JrcRelationship::Configuration.create!(account: sd_account, rules: { auto_handoff: false })
    report = JrcRelationship::Backfill.new(context: context).call(apply: true)
    expect(report[:excluded]['auto_handoff_disabled']).to eq(1)
    expect(JrcRelationship::Assignment.where(account: sd_account)).not_to exist
  end

  it 'REL-04 persists factors, weights, evidence and configuration version in authorized history' do
    JrcRelationship::Processor.new(context: context, assignment: assignment).call
    snapshot = JrcRelationship::HealthSnapshot.where(assignment: assignment).last
    expect(snapshot.viewer_id).to eq(sd_user.id)
    expect(snapshot.access_signature).to eq(context.access_signature)
    expect(snapshot.factors).to all(include('factor', 'weight', 'contribution', 'evidence'))
    expect(snapshot.config_version).to eq(context.configuration(assignment).version)
  end

  it 'REL-05 generates one native action for a health decline even across days' do
    JrcRelationship::Processor.new(context: context, assignment: assignment).call
    assignment.update!(created_at: 45.days.ago)
    JrcRelationship::Processor.new(context: context, assignment: assignment).call
    action = assignment.actions.find_by!(kind: 'health_drop')
    workflow.save(kind: 'actions', id: action.id, attributes: { assignment_id: assignment.id, lock_version: action.lock_version,
      status: 'waiting_customer' })
    travel_to 1.day.from_now do
      JrcRelationship::Processor.new(context: context, assignment: assignment).call
      expect(assignment.actions.where(kind: 'health_drop').count).to eq(1)
    end
    expect(action.reload.activity).to be_present
  end

  it 'REL-06 exposes severity, customer health and MRR in the operational risk row' do
    JrcRelationship::Processor.new(context: context, assignment: assignment).call
    risk = workflow.save(kind: 'risks', attributes: { assignment_id: assignment.id, request_id: SecureRandom.uuid,
      severity: 'high', reason: 'Controlled test risk', due_at: 1.day.from_now })[:record]
    presenter = JrcRelationship::Presenter.new(context)
    presenter.preload([assignment])
    data = presenter.record(risk)
    expect(data).to include('severity' => 'high', 'mrr_cents' => 0, 'origin' => 'manual', 'owner_name' => sd_user.name)
    expect(data['health']).to include('score', 'band')
    expect(data['due_at']).to be_present
  end

  it 'REL-07 saves metrics, milestones, observations and native activity references atomically' do
    activity = workflow.activity!(assignment: assignment, title: 'Native plan task', due_at: 1.day.from_now, request_id: SecureRandom.uuid)
    data = { assignment_id: assignment.id, request_id: SecureRandom.uuid, title: 'Controlled success plan', target_on: 30.days.from_now.to_date,
      notes: 'Observed usage', goals: [{ metric: 'usage', baseline: 1, current: 2, target: 10, activity_id: activity.id, evidence: 'Native activity' }],
      milestones: [{ title: 'Review adoption', status: 'active', owner_id: sd_user.id, due_at: 1.day.from_now.iso8601, activity_id: activity.id }] }
    plan = workflow.save(kind: 'plans', attributes: data)[:record].reload
    expect(plan.goals.first).to include('baseline' => 1, 'current' => 2, 'target' => 10, 'activity_id' => activity.id)
    expect(plan.metadata).to include('notes' => 'Observed usage')
    expect(plan.metadata['milestones'].first['activity_id']).to eq(activity.id)
    foreign = JrcCrm::Activity.create!(account: sd_foreign_account, user: create(:user, account: sd_foreign_account),
      contact: create(:contact, account: sd_foreign_account), activity_type: 'task', title: 'Foreign task', due_at: 1.day.from_now)
    expect { workflow.save(kind: 'plans', attributes: data.merge(request_id: SecureRandom.uuid,
      goals: [{ metric: 'usage', activity_id: foreign.id }])) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcRelationship::SuccessPlan.where(account: sd_account).count).to eq(1)
  end

  it 'REL-08 persists internal/external participants and projects each decision to native Agenda once' do
    fields = { assignment_id: assignment.id, request_id: SecureRandom.uuid, title: 'Controlled QBR', scheduled_at: 1.day.from_now,
      status: 'completed', summary: 'Customer agreed next steps', participants: [{ participant_type: 'internal', user_id: sd_user.id },
        { participant_type: 'external', name: 'Customer representative', email: 'customer@example.test' }],
      decisions: [{ title: 'Review results', due_at: 2.days.from_now.iso8601, owner_id: sd_user.id }] }
    qbr = workflow.save(kind: 'qbrs', attributes: fields)[:record]
    workflow.save(kind: 'qbrs', id: qbr.id, attributes: fields.merge(lock_version: qbr.reload.lock_version))
    follow_up = JrcCrm::Activity.find_by!(account: sd_account, title: 'Review results')
    expect(JrcCrm::Activity.where(account: sd_account, title: 'Review results').count).to eq(1)
    expect(qbr.reload.participants.first['user_id']).to eq(sd_user.id)
    expect(assignment.actions.find_by!(activity_id: qbr.activity_id).status).to eq('completed')
    action = assignment.actions.find_by!(activity_id: follow_up.id)
    expect(action.operations_queue).to be_present
    expect(action.operations_sla_policy).to be_present
    agenda = JrcOperations::Agenda.new(account_user: sd_account_user, filters: { source: 'crm', from: Date.current.iso8601,
      to: 3.days.from_now.to_date.iso8601 }).call
    expect(agenda[:data].pluck(:activity_id)).to include(follow_up.id)
    changed = 3.days.from_now.change(usec: 0)
    workflow.save(kind: 'qbrs', id: qbr.id, attributes: fields.merge(lock_version: qbr.reload.lock_version,
      decisions: [{ title: 'Updated follow-up', due_at: changed.iso8601, owner_id: sd_user.id }]))
    expect(follow_up.reload.title).to eq('Updated follow-up')
    expect(follow_up.due_at).to eq(changed)
    expect(assignment.actions.find_by!(activity_id: follow_up.id).due_at).to eq(changed)
  end

  it 'REL-08 rejects an internal participant from another Account before creating commitments' do
    foreign = create(:user, account: sd_foreign_account)
    expect { workflow.save(kind: 'qbrs', attributes: { assignment_id: assignment.id, title: 'Unauthorized attendee',
      scheduled_at: 1.day.from_now, participants: [{ participant_type: 'internal', user_id: foreign.id }] }) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcRelationship::Qbr.where(account: sd_account)).not_to exist
  end
end

require 'rails_helper'
RSpec.describe 'Relationship complementary review' do
  include_context 'JRC Service Desk domain'
  let(:company) { sd_account.master_companies.create!(name: 'CS complementary native customer') }
  let(:assignment) { JrcRelationship::Assignment.create!(account: sd_account, company: company, owner: sd_user, status: 'active') }
  let(:context) { JrcRelationship::Context.new(sd_account_user) }
  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm', 'jrc_projects')
    sd_contact.update!(master_company: company)
  end
  it 'creates native plan, welcome meeting and follow-ups idempotently without new customer copies' do
    2.times { JrcRelationship::Playbooks.new(context).run!(assignment, 'onboarded') }
    plans = JrcRelationship::SuccessPlan.where(assignment: assignment)
    expect(plans.count).to eq(1)
    expect(plans.first.metadata['milestones'].map { |m| m['status'] }).to eq(%w[active active active])
    expect(assignment.actions.joins(:activity).where(jrc_crm_activities: { activity_type: 'meeting' }).count).to eq(1)
    expect(assignment.actions.joins(:activity).where(jrc_crm_activities: { activity_type: 'task' }).count).to eq(3)
    expect(sd_account.master_companies.where(id: company.id).count).to eq(1)
  end
  it 'runs configured risk once using the existing retention and operational SLA workflows' do
    book = JrcRelationship::Playbook.create!(account: sd_account, name: 'Recovery', trigger_kind: 'no_contact',
      steps: [{ kind: 'risk', title: 'Recover relationship', after_days: 0 }])
    2.times { JrcRelationship::Playbooks.new(context).run!(assignment, 'no_contact', source_key: 'test-event', playbook_id: book.id) }
    expect(JrcRelationship::RiskCase.where(assignment: assignment).count).to eq(1)
    expect(assignment.actions.where(kind: 'retention').count).to eq(1)
    expect(assignment.actions.find_by!(kind: 'retention').operations_sla_policy).to be_present
  end
  it 'rejects a configuration scope pointing outside the current Account' do
    taxonomy = JrcCustomers::Taxonomy.create!(account: create(:account), kind: 'segment', name: 'Other Account')
    config = JrcRelationship::Configuration.new(account: sd_account, scope_key: "segment:#{taxonomy.id}")
    expect(config).not_to be_valid
  end
  it 'does not create operational work when a read-only viewer recalculates cached health' do
    policy = context.policy
    allow(policy).to receive(:manage?).and_return(false)
    allow(context).to receive(:policy).and_return(policy)
    JrcRelationship::Processor.new(context: context, assignment: assignment).call
    expect(assignment.actions).to be_empty
    expect(JrcRelationship::RiskCase.where(assignment: assignment)).to be_empty
    expect(JrcRelationship::HealthSnapshot.where(assignment: assignment, viewer: sd_user)).to exist
  end
  it 'reconciles open expansion separately from actual CRM wins without duplicate conversion' do
    pipeline = create(:jrc_crm_pipeline, account: sd_account)
    stage = create(:jrc_crm_stage, account: sd_account, pipeline: pipeline)
    flow = JrcRelationship::Workflow.new(context)
    signal = flow.save(kind: 'expansion', attributes: { assignment_id: assignment.id, request_id: SecureRandom.uuid,
      title: 'Qualified expansion', potential_cents: 200_000 })[:record]
    deal = flow.opportunity!(signal, pipeline_id: pipeline.id, stage_id: stage.id)
    expect(JrcRelationship::ExpansionPipeline.open(context.records(JrcRelationship::ExpansionSignal), sd_account.jrc_crm_deals)).to include(signal.reload)
    deal.update!(status: 'won')
    dashboard = JrcRelationship::Presenter.new(context).dashboard(context.assignments)
    expect(dashboard[:expansion_potential_cents]).to eq(0)
    expect(dashboard[:expansion_won_cents]).to eq(200_000)
    data = JrcRelationship::Presenter.new(context).record(signal.reload)
    expect(data['commercial_context']).to include(won_cents: 200_000)
    expect(data['commercial_context'][:deal][:status]).to eq('won')
    expect(flow.opportunity!(signal, pipeline_id: pipeline.id, stage_id: stage.id).id).to eq(deal.id)
  end
  it 'preserves the configured question in the survey and applies frequency limits' do
    JrcRelationship::Configuration.create!(account: sd_account, rules: { survey_question_nps: 'Configured NPS question?' })
    flow = JrcRelationship::Workflow.new(context)
    attrs = { assignment_id: assignment.id, request_id: SecureRandom.uuid, kind: 'nps' }
    survey = flow.save(kind: 'surveys', attributes: attrs)[:record]
    expect(survey.metadata['question']).to eq('Configured NPS question?')
    expect { flow.save(kind: 'surveys', attributes: attrs) }.to raise_error(ArgumentError, /frequency/)
  end

  it 'withdraws only removed QBR commitments without reusing the next native task' do
    flow = JrcRelationship::Workflow.new(context)
    fields = { assignment_id: assignment.id, request_id: SecureRandom.uuid, title: 'Review', summary: 'Meeting reviewed',
      scheduled_at: Time.current, status: 'completed', decisions: [
        { title: 'First', due_at: 1.day.from_now.iso8601, decision_key: 'first' },
        { title: 'Second', due_at: 2.days.from_now.iso8601, decision_key: 'second' }] }
    qbr = flow.save(kind: 'qbrs', attributes: fields)[:record]
    removed = assignment.actions.find_by!(source_key: "activity:qbr:#{qbr.id}:decision:first")
    kept = assignment.actions.find_by!(source_key: "activity:qbr:#{qbr.id}:decision:second")
    flow.save(kind: 'qbrs', id: qbr.id, attributes: { assignment_id: assignment.id, lock_version: qbr.lock_version,
      decisions: fields[:decisions].last(1) })
    expect(removed.reload.status).to eq('dismissed')
    expect(removed.activity.reload.status).to eq('cancelled')
    expect(kept.reload.status).to eq('open')
    expect(kept.activity.reload.title).to eq('Second')
    expect(assignment.actions.where('source_key LIKE ?', "activity:qbr:#{qbr.id}:decision:%").count).to eq(2)
  end

  it 'preserves a manager priority during automatic refresh and retains calculated evidence' do
    processor = JrcRelationship::Processor.new(context: context, assignment: assignment)
    rules = context.configuration(assignment).effective_rules
    data = { health: { score: 100 }, mrr_cents: 0, days_without_contact: 0, renewal_on: Date.current + 120,
      critical_tickets: 0, sla_breached: 0, _source_ids: {} }
    action = processor.action!('health', 'Priority review', data, rules)
    flow = JrcRelationship::Workflow.new(context)
    flow.save(kind: 'actions', id: action.id, attributes: { assignment_id: assignment.id, lock_version: action.lock_version, priority: 88 })
    expect(action.reload.metadata['manual_priority']).to be(true)
    processor.action!('health', 'Priority review', data.merge(health: { score: 20 }), rules)
    expect(action.reload.priority).to eq(88)
    expect(action.factors.dig('health', 'normalized')).to eq(80)
    expect(assignment.actions.where(kind: 'health').count).to eq(1)
    expect(action.activity.reload.metadata['relationship_action_id'].to_i).to eq(action.id)
  end

end

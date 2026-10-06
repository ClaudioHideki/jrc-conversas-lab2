require 'rails_helper'

# Requires additive migrations in an isolated PostgreSQL TEST database.
RSpec.describe 'Relationship native lifecycle' do
  include_context 'JRC Service Desk domain'
  let(:company) { sd_account.master_companies.create!(name: 'CS native customer') }
  let(:assignment) { JrcRelationship::Assignment.find_or_create_by!(account: sd_account, company: company) { |row| row.owner = sd_user; row.status = 'active' } }
  let(:context) { JrcRelationship::Context.new(sd_account_user) }
  let(:workflow) { JrcRelationship::Workflow.new(context) }
  let(:order) { JrcCrm::SalesOrder.create!(account: sd_account, owner: sd_user, contact: sd_contact, source_type: 'manual', order_origin: 'direct_sale', status: 'completed', monthly_cents: 100_000) }
  let(:signed_contract) do
    contract = JrcCrm::Contract.create!(account: sd_account, sales_order: order, owner: sd_user, contact: sd_contact,
      status: 'draft', ends_on: 60.days.from_now.to_date)
    contract.signed_document.attach(io: StringIO.new("%PDF-1.4\n1 0 obj <</Type /Catalog>> endobj\nstartxref\n0\n%%EOF"),
      filename: 'signed-contract.pdf', content_type: 'application/pdf')
    contract.update!(status: 'active', signature_status: 'signed', signature_mode: 'manual', signed_at: Time.current, signed_by_name: 'Cliente')
    contract
  end
  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm', 'jrc_projects')
    sd_contact.update!(company_id: company.id)
  end

  def process
    JrcRelationship::Processor.new(context: context, assignment: assignment).call
  end

  def save(kind, fields = {}, record: nil, **values)
    workflow.save(kind: kind, id: record&.id, attributes: { assignment_id: assignment.id, request_id: SecureRandom.uuid,
      lock_version: record&.lock_version }.merge(fields).merge(values))[:record]
  end

  it 'REL-001 creates a single portfolio and onboarding playbook after implantation' do
    signed_contract
    source = JrcCrm::BackofficeRequest.create!(account: sd_account, sales_order: order, owner: sd_user, requested_by: sd_user,
      contact: sd_contact, title: 'Implantação concluída', stage: 'completed', status: 'completed')
    2.times { JrcRelationship::SignalJob.perform_now(source.class.name, source.id) }
    expect(JrcRelationship::Assignment.where(account: sd_account, company: company).count).to eq(1)
    expect(JrcRelationship::Action.where(assignment: assignment, source_key: 'handoff').count).to eq(1)
    activities = JrcCrm::Activity.where(account: sd_account).where("metadata ->> 'relationship_assignment_id' = ?", assignment.id.to_s)
    expect(activities.count).to eq(5)
    expect(activities.where(activity_type: 'meeting').count).to eq(1)
    plans = JrcRelationship::SuccessPlan.where(assignment: assignment)
    expect(plans.count).to eq(1)
    expect(plans.first.metadata['milestones'].size).to eq(3)
  end

  it 'REL-002/CS-03 changes health band and evaluates critical risk without duplicate actions' do
    weights = JrcRelationship::Configuration::DEFAULT_WEIGHTS.transform_values { 0 }.merge('relationship' => 100)
    JrcRelationship::Configuration.create!(account: sd_account, weights: weights)
    assignment.update!(created_at: 40.days.ago)
    2.times { process }
    expect(JrcRelationship::HealthSnapshot.where(assignment: assignment).last.band).to eq('critical')
    expect(assignment.actions.where(kind: 'health').count).to eq(1)
    expect(assignment.actions.find_by!(kind: 'health').priority).to be >= 90
    expect(JrcRelationship::RiskCase.find_by!(assignment: assignment, kind: 'health').severity).to eq('critical')
  end

  it 'evaluates health decline against the previous authorized snapshot once' do
    process
    assignment.update!(created_at: 40.days.ago)
    2.times { process }
    expect(assignment.actions.where(kind: 'health_drop').count).to eq(1)
    expect(assignment.actions.find_by!(kind: 'health_drop').priority).to be >= 70
    expect(JrcRelationship::HealthSnapshot.where(assignment: assignment).last.signals.dig('health_change', 'drop')).to be >= 20
  end

  it 'REL-003 includes the real critical ticket in health, action and the existing timeline' do
    sd_priority.update!(code: 'P1')
    ticket = sd_ticket
    process
    expect(JrcRelationship::HealthSnapshot.where(assignment: assignment).last.signals['critical_tickets']).to eq(1)
    expect(assignment.actions.find_by!(kind: 'ticket').priority).to be >= 85
    expect(assignment.customer_context(sd_account_user).tickets).to include(ticket)
    expect(assignment.customer_context(sd_account_user).timeline_sources.keys).to include('ticket_event', 'audit')
  end

  it 'REL-004/CS-05 processes the real relational NPS response once' do
    survey = save('surveys', kind: 'nps')
    survey.update!(score: 3, responded_at: Time.current)
    2.times { JrcRelationship::SignalJob.perform_now(survey.class.name, survey.id) }
    expect(assignment.actions.where(kind: 'satisfaction').count).to eq(1)
    expect(JrcRelationship::RiskCase.where(assignment: assignment, kind: 'satisfaction').count).to eq(1)
    expect(JrcRelationship::Presenter.new(context).dashboard(context.assignments)[:nps]).to eq(-100)
  end

  it 'REL-005/CS-02 creates a preventive action after thirty days without contact' do
    assignment.update!(created_at: 31.days.ago)
    2.times { process }
    expect(assignment.actions.where(kind: 'no_contact').count).to eq(1)
  end

  it 'REL-006/CS-04 opens the existing contract sixty-day renewal without duplicates' do
    contract = signed_contract
    2.times { process }
    expect(JrcRelationship::Renewal.where(contract: contract).count).to eq(1)
    expect(JrcRelationship::Presenter.new(context).dashboard(context.assignments)[:renewals][60]).to eq(1)
  end

  it 'REL-03 reconciles management MRR with active native contracts before any health snapshot exists' do
    signed_contract
    assignment
    dashboard = JrcRelationship::Presenter.new(context).dashboard(context.assignments)
    team = JrcRelationship::TeamMetrics.new(context: context, scope: context.assignments).call
    expect(dashboard[:mrr_cents]).to eq(100_000)
    expect(team.fetch(sd_user.id)[:mrr_cents]).to eq(dashboard[:mrr_cents])
  end

  it 'REL-007 creates exactly one real CRM opportunity with traceable origin' do
    pipeline = create(:jrc_crm_pipeline, account: sd_account)
    stage = create(:jrc_crm_stage, account: sd_account, pipeline: pipeline)
    signal = save('expansion', title: 'Novo produto', potential_cents: 200_000)
    first = workflow.opportunity!(signal, pipeline_id: pipeline.id, stage_id: stage.id)
    second = workflow.opportunity!(signal.reload, pipeline_id: pipeline.id, stage_id: stage.id)
    expect(first).to be_a(JrcCrm::Deal)
    expect(second.id).to eq(first.id)
    expect(first.metadata['origin']).to eq('relationship')
    expect(first.contact).to eq(sd_contact)
    expect(first.company).to eq(company)
    expect(first.owner).to eq(signal.owner)
  end

  it 'keeps the chosen CS responsible when a manager converts expansion into a CRM deal' do
    responsible = create(:user, account: sd_account)
    pipeline = create(:jrc_crm_pipeline, account: sd_account)
    stage = create(:jrc_crm_stage, account: sd_account, pipeline: pipeline)
    signal = save('expansion', title: 'Expansão acompanhada', potential_cents: 200_000)
    signal.update!(owner: responsible)
    deal = workflow.opportunity!(signal, pipeline_id: pipeline.id, stage_id: stage.id)
    expect(deal.owner).to eq(responsible)
    expect(deal.metadata['relationship_resource_id']).to eq(signal.id)
  end

  it 'REL-008 opens retention for the actual cancellation request and keeps original history' do
    assignment
    source = JrcCrm::BackofficeRequest.create!(account: sd_account, sales_order: order, owner: sd_user, requested_by: sd_user,
      contact: sd_contact, request_kind: 'cancellation', title: 'Pedido de cancelamento')
    2.times { JrcRelationship::SignalJob.perform_now(source.class.name, source.id) }
    expect(JrcRelationship::RiskCase.where(assignment: assignment, kind: 'cancellation').count).to eq(1)
    risk = JrcRelationship::RiskCase.find_by!(assignment: assignment, kind: 'cancellation')
    action = assignment.actions.find_by!(source_key: "risk:#{risk.id}")
    expect(action.operations_queue).to be_present
    expect(action.operations_sla_policy).to be_present
    expect(action.activity).to be_present
    expect(action.priority).to eq(90)
    expect(assignment.actions.where(source_key: "risk:#{risk.id}").count).to eq(1)
    expect(source.reload.request_kind).to eq('cancellation')
    expect(assignment.customer_context(sd_account_user).audits.where(event_type: 'relationship_updated')).to exist
  end

  it 'REL-009 rejects another tenant and customer reparenting' do
    foreign = JrcRelationship::Assignment.create!(account: sd_foreign_account, contact: create(:contact, account: sd_foreign_account))
    expect { context.assignment(foreign.id) }.to raise_error(ActiveRecord::RecordNotFound)
    record = save('actions', reason: 'Follow-up')
    other = JrcRelationship::Assignment.create!(account: sd_account, contact: create(:contact, account: sd_account), owner: sd_user)
    expect { workflow.save(kind: 'actions', id: record.id, attributes: { assignment_id: other.id, lock_version: record.lock_version, reason: 'Move' }) }.to raise_error(ArgumentError, /origin/)
  end

  it 'REL-010 creates native QBR minutes, follow-up and timeline once' do
    qbr = save('qbrs', title: 'QBR trimestral', scheduled_at: 1.day.from_now)
    qbr = save('qbrs', { status: 'completed', summary: 'Ata confirmada', decisions: [{ 'title' => 'Enviar plano', 'due_at' => 2.days.from_now.iso8601 }] }, record: qbr)
    save('qbrs', { status: 'completed', summary: 'Ata confirmada' }, record: qbr.reload)
    expect(qbr.reload.activity).to be_completed
    expect(JrcCrm::Activity.where(account: sd_account, title: 'Enviar plano').count).to eq(1)
    expect(assignment.customer_context(sd_account_user).activities).to include(qbr.activity)
    agenda = JrcOperations::Agenda.new(account_user: sd_account_user, filters: { source: 'crm', from: Date.current.iso8601, to: 3.days.from_now.to_date.iso8601 }).call
    expect(agenda[:data].map { |row| row[:activity_id] }).to include(qbr.activity_id)
    expect(assignment.customer_context(sd_account_user).audits.where(resource_type: qbr.class.name, resource_id: qbr.id)).to exist
  end

  it 'REL-011 consumes actual overdue balance, not a mock financial score' do
    JrcCrm::Invoice.create!(account: sd_account, sales_order: order, contact: sd_contact, due_on: 1.day.ago.to_date, balance_cents: 10_000, total_cents: 10_000, status: 'overdue')
    data = process
    expect(data[:overdue_cents]).to eq(10_000)
    finance = data[:health][:factors].find { |factor| factor[:factor] == 'finance' }
    expect(finance[:raw]).to eq(10_000)
    expect(finance[:normalized]).to eq(context.configuration.effective_rules['overdue_finance_score'])
    expect(assignment.actions.where(kind: 'finance')).to exist
  end

  it 'REL-012 closes retained risk with outcome and updates real metrics' do
    risk = save('risks', reason: 'Risco manual')
    risk = save('risks', { status: 'retained', outcome: 'Cliente confirmou continuidade' }, record: risk)
    expect(risk.closed_at).to be_present
    expect(assignment.reload.status).to eq('active')
    metrics = JrcRelationship::Presenter.new(context).dashboard(context.assignments)
    expect(metrics[:retained]).to eq(1)
    expect(metrics[:retention_rate]).to eq(100)
  end

  it 'CS-09 records completion actor, date, result and audit' do
    action = save('actions', reason: 'Contato de recuperação')
    action = save('actions', { status: 'completed', result: 'Contato realizado' }, record: action)
    expect(action.completed_by).to eq(sd_user)
    expect(action.completed_at).to be_present
    expect(action.result).to eq('Contato realizado')
    expect(JrcCrm::AuditEvent.where(account: sd_account, resource_type: action.class.name, resource_id: action.id).last.actor_id).to eq(sd_user.id)
  end

  it 'blocks derived financial actions and historical scores after source access is revoked' do
    JrcCrm::Invoice.create!(account: sd_account, sales_order: order, contact: sd_contact, due_on: 1.day.ago.to_date,
      balance_cents: 10_000, total_cents: 10_000, status: 'overdue')
    process
    expect(context.records(JrcRelationship::Action).where(kind: 'finance')).to exist
    sd_account.disable_features!('jrc_crm')
    fresh = JrcRelationship::Context.new(sd_account_user.reload)
    expect(fresh.records(JrcRelationship::Action).where(kind: 'finance')).not_to exist
    expect(fresh.records(JrcRelationship::Renewal)).not_to exist
    history = JrcRelationship::HealthSnapshot.where(assignment: assignment)
    expect(JrcRelationship::SnapshotAccess.scope(fresh, history)).not_to exist
  end

  it 'requires native opportunity conversion instead of a manual expansion approval' do
    expect { save('expansion', title: 'Expansão', status: 'approved') }.to raise_error(ArgumentError, /CRM/)
    expect(JrcCrm::Deal.where(account: sd_account)).not_to exist
  end

  it 'keeps the effective configuration scope and version in each health snapshot' do
    product = create(:jrc_crm_product, account: sd_account)
    JrcRelationship::Configuration.create!(account: sd_account, scope_key: "product:#{product.id}", version: 3)
    assignment.update!(settings: { product_id: product.id })
    process
    snapshot = JrcRelationship::HealthSnapshot.where(assignment: assignment).last
    expect(snapshot.config_version).to eq(3)
    expect(snapshot.config_scope_key).to eq("product:#{product.id}")
  end

  it 'rejects a repeated survey during its configured frequency window' do
    save('surveys', kind: 'nps')
    expect { save('surveys', kind: 'nps') }.to raise_error(ArgumentError, /frequency/)
  end

  it 'rejects stale edits instead of overwriting a concurrent change' do
    action = save('actions', reason: 'Original')
    version = action.lock_version
    save('actions', { reason: 'Atualizado' }, record: action)
    expect { workflow.save(kind: 'actions', id: action.id, attributes: { assignment_id: assignment.id, lock_version: version, reason: 'Stale' }) }.to raise_error(ActiveRecord::StaleObjectError)
  end
end

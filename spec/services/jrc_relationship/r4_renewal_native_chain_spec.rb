require 'rails_helper'

RSpec.describe JrcRelationship::RenewalOutcome do
  include_context 'JRC Service Desk domain'
  let(:company) { sd_account.master_companies.create!(name: 'Canonical renewal company') }
  let(:assignment) { JrcRelationship::Assignment.create!(account: sd_account, company: company, owner: sd_user, status: 'active') }
  let(:context) { JrcRelationship::Context.new(sd_account_user) }
  let(:workflow) { JrcRelationship::Workflow.new(context) }
  let(:pipeline) { create(:jrc_crm_pipeline, account: sd_account) }
  let(:stage) { create(:jrc_crm_stage, account: sd_account, pipeline: pipeline) }
  let(:product) { create(:jrc_crm_product, account: sd_account, billing_model: 'monthly', requires_contract: true, unit_price_cents: 120_000) }
  let(:original) do
    row = approved_order.contracts.find_by!(source_contract_id: nil)
    row.update!(starts_on: 1.year.ago.to_date, ends_on: Date.current + 10)
    sign!(row)
  end
  let(:renewal) do
    JrcRelationship::Renewal.create!(account: sd_account, assignment: assignment, owner: sd_user, contract: original,
                                      renewal_on: original.ends_on, status: 'open')
  end

  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_crm', 'jrc_relationship')
    sd_contact.update!(company_id: company.id)
    assignment
  end

  def sign!(row)
    row.signed_document.attach(io: StringIO.new("%PDF-1.4\n1 0 obj <</Type /Catalog>> endobj\nstartxref\n0\n%%EOF"),
                               filename: 'native-renewal.pdf', content_type: 'application/pdf')
    row.update!(status: 'active', signature_status: 'signed', signature_mode: 'manual', signed_at: Time.current, signed_by_name: 'Test customer')
    row
  end

  def approved_order(monthly_cents = 100_000, source_contract: nil)
    order = JrcCrm::SalesOrder.create!(account: sd_account, owner: sd_user, contact: sd_contact, source_type: 'manual',
                                     order_origin: source_contract ? 'renewal' : 'direct_sale', status: 'pending', monthly_cents: monthly_cents,
                                     snapshot: { 'source_contract_id' => source_contract&.id }.compact)
    request = order.backoffice_requests.find_by!(request_kind: 'approval')
    JrcCrm::OrderApprovalService.new(order: order, actor: sd_user).decide!(request: request, decision: 'approved')
    order.reload
  end

  def mark_won(selected = nil)
    workflow.save(kind: 'renewals', id: renewal.id, attributes: { assignment_id: assignment.id, lock_version: renewal.reload.lock_version,
                                                                  status: 'won', renewed_contract_id: selected })
  end

  def successor
    order = approved_order(120_000, source_contract: original)
    sign!(order.contracts.find_by!(source_contract_id: original.id))
  end

  it 'requires a canonical contact selection instead of choosing the first company contact' do
    expect { workflow.opportunity!(renewal, pipeline_id: pipeline.id, stage_id: stage.id) }.to raise_error(ArgumentError, /contact/i)
    foreign = create(:contact, account: sd_foreign_account)
    expect { workflow.opportunity!(renewal, pipeline_id: pipeline.id, stage_id: stage.id, contact_id: foreign.id) }
      .to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcCrm::Deal.where(account: sd_account)).not_to exist
    deal = workflow.opportunity!(renewal, pipeline_id: pipeline.id, stage_id: stage.id, contact_id: sd_contact.id)
    expect(deal).to have_attributes(company_id: company.id, contact_id: sd_contact.id)
    expect(workflow.opportunity!(renewal.reload, pipeline_id: pipeline.id, stage_id: stage.id, contact_id: sd_contact.id).id).to eq(deal.id)
  end

  it 'rejects manual won, draft successors and ended signatures as renewal evidence' do
    expect { mark_won }.to raise_error(ArgumentError, /signed|active/i)
    draft = approved_order(100_000, source_contract: original).contracts.find_by!(source_contract_id: original.id)
    expect { mark_won(draft.id) }.to raise_error(ActiveRecord::RecordNotFound)
    signed = successor
    signed.update!(status: 'ended')
    expect(described_class.new(context, renewal).resolve).to be_nil
    expect(described_class.cohort(context, [renewal])).to include(renewed_count: 0, source_count: 1)
  end

  it 'requires an explicit successor when multiple active signed contracts exist and audits the exact proof once' do
    one = successor
    two = successor
    JrcRelationship::RenewalReconciliation.new(context, assignment).call
    expect(renewal.reload.status).to eq('open')
    expect(described_class.cohort(context, [renewal])).to include(ambiguous_source_count: 1, renewed_count: 0)
    mark_won(two.id)
    expect(renewal.reload.metadata).to include('renewed_contract_id' => two.id, 'source_contract_id' => original.id)
    outcome = described_class.cohort(context, [renewal, renewal])
    expect(outcome).to include(source_count: 1, renewed_count: 1)
    expect(outcome[:contracts].pluck(:id)).to eq([two.id])
    expect(outcome[:contracts].pluck(:id)).not_to include(one.id)
  end

  it 'revalidates signed successor and canonical customer visibility after commercial access is revoked' do
    successor
    sd_account.disable_features!('jrc_crm')
    fresh = JrcRelationship::Context.new(sd_account_user.reload)
    expect { described_class.new(fresh, renewal).resolve }.to raise_error(ActiveRecord::RecordNotFound)
  end

  def accepted_order
    deal = workflow.opportunity!(renewal, pipeline_id: pipeline.id, stage_id: stage.id, contact_id: sd_contact.id)
    create(:jrc_crm_stage, account: sd_account, pipeline: pipeline, is_won: true, is_terminal: true, key: 'r4-won')
    proposal = accepted_proposal(deal)
    lifecycle = JrcCrm::AcceptedProposalLifecycleService.new(proposal: proposal.reload, actor: sd_user).call
    { deal: deal, proposal: proposal, lifecycle: lifecycle, order: lifecycle.fetch(:order) }
  end

  def accepted_proposal(deal)
    deal.deal_products.create!(product: product, quantity: 1, unit_price_cents: 120_000)
    proposal = JrcCrm::ProposalBuilderService.new(deal: deal, actor: sd_user).call
    proposal.update!(status: 'sent', sent_at: Time.current)
    proposal.accept_by_customer!(name: 'Test customer', document: 'TEST-DOCUMENT', remote_ip: '127.0.0.1', user_agent: 'RSpec')
    proposal
  end

  def approve_renewal_order(order)
    sd_account.jrc_crm_contract_templates.create!(name: 'Renewal template', body: 'Native renewal contract', active: true)
    approval = order.backoffice_requests.find_by!(request_kind: 'approval')
    JrcCrm::OrderApprovalService.new(order: order, actor: sd_user).decide!(request: approval, decision: 'approved')
    order.reload.contracts.find_by!(source_contract_id: original.id)
  end

  it 'executes proposal acceptance and actual Backoffice approval but still requires contract signature' do
    chain = accepted_order
    proposal = chain.fetch(:proposal)
    order = chain.fetch(:order)
    expect(chain[:lifecycle][:success]).to be(true), chain[:lifecycle].inspect
    expect(order).to have_attributes(contact_id: sd_contact.id, deal_id: chain[:deal].id, order_origin: 'renewal')
    expect(order.snapshot['source_contract_id']).to eq(original.id)
    expect(proposal.sales_orders.count).to eq(1)
    expect(described_class.new(context, renewal.reload).resolve).to be_nil
    contract = approve_renewal_order(order)
    expect(contract.status).to eq('draft')
    expect { mark_won(contract.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'reconciles the complete signed native chain once and exposes exact renewal financial denominators' do
    chain = accepted_order
    proposal = chain.fetch(:proposal)
    order = chain.fetch(:order)
    contract = approve_renewal_order(order)
    sign!(contract)
    2.times { JrcRelationship::RenewalReconciliation.new(context, assignment).call }
    expect(renewal.reload).to have_attributes(status: 'won', deal_id: chain[:deal].id)
    expect(renewal.metadata).to include('renewed_contract_id' => contract.id, 'renewal_order_id' => order.id, 'renewal_deal_id' => chain[:deal].id)
    events = sd_account.jrc_crm_audit_events.where(resource_type: renewal.class.name, resource_id: renewal.id)
                       .where("metadata ->> 'action' = 'renewal_commercial_result'")
    expect(events.count).to eq(1)
    replay = JrcCrm::AcceptedProposalLifecycleService.new(proposal: proposal.reload, actor: sd_user).call
    expect(replay[:order].id).to eq(order.id)
    metrics = JrcRelationship::Presenter.new(context).dashboard(context.assignments, period: Time.current..20.days.from_now)
    expect(metrics).to include(renewal_rate: 100.0, renewed_mrr_cents: contract.monthly_cents,
                               renewal_coverage: hash_including(source_count: 1, renewed_count: 1))
    drilldown = JrcRelationship::MetricDrilldown.new(context: context, scope: context.assignments,
                                                     period: Time.current..20.days.from_now).call(metric: 'renewal_rate')
    expect(drilldown[:calculation]).to include(numerator: 1, denominator: 1)
    expect(drilldown[:payload].pluck(:id)).to include(renewal.id)
  end
end

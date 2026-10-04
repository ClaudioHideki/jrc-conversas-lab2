require 'rails_helper'

RSpec.describe 'JRC CRM Nexora end-to-end commercial lifecycle' do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :administrator, name: 'Thiago Ribeiro') }

  before do
    account.enable_features!('jrc_crm', 'jrc_customer_master', 'jrc_projects')
  end

  it 'preserves one company/contact from lead through won sale, order, contract, backoffice and implementation project' do
    company = JrcCustomers::CompanyWriter.new(account: account, actor: seller).save!(
      company: account.master_companies.new,
      attributes: {
        name: 'Nexora Tecnologia Ltda.',
        trade_name: 'Nexora Tech',
        person_kind: 'organization',
        relationship_type: 'prospect',
        size: 'epp',
        source: 'website',
        active: true
      }
    )
    contact = create(
      :contact,
      account: account,
      company_id: company.id,
      name: 'Marcelo Andrade',
      email: 'marcelo.andrade@nexora.example'
    )

    pipeline = JrcCrm::Pipeline.create!(account: account, name: 'Novas Vendas', key: 'novas-vendas', position: 1)
    opportunity = JrcCrm::Stage.create!(
      account: account, pipeline: pipeline, name: 'Oportunidade qualificada', key: 'qualified', position: 1,
      probability: 40, active: true
    )
    JrcCrm::Stage.create!(
      account: account, pipeline: pipeline, name: 'Fechado / Ganho', key: 'won', position: 2,
      probability: 100, active: true, is_terminal: true, is_won: true
    )

    lead = JrcCrm::Lead.create!(
      account: account,
      owner: seller,
      contact: contact,
      company: company,
      name: 'Nexora Tech — JRC Conversas',
      company_name: company.name,
      email: contact.email,
      source: 'website',
      status: 'qualified',
      custom_attributes: {
        'product_interest' => 'JRC Conversas',
        'estimated_users' => 10,
        'need' => 'Unificar WhatsApp, telefonia e CRM',
        'decision_maker' => 'Marcelo Andrade',
        'budget_confirmed' => true,
        'deadline_days' => 30
      }
    )

    conversion = JrcCrm::LeadConversionService.new(
      lead: lead,
      account: account,
      actor: seller,
      params: {
        pipeline_id: pipeline.id,
        stage_id: opportunity.id,
        company_id: company.id,
        deal_title: 'Nexora Tech — Implantação JRC Conversas',
        value_cents: 100_000,
        expected_close_at: 30.days.from_now
      }
    ).call
    expect(conversion[:success]).to be(true)
    deal = conversion[:deal]
    expect(deal.company_id).to eq(company.id)
    expect(deal.contact_id).to eq(contact.id)

    demonstration = JrcCrm::Activity.create!(
      account: account, user: seller, deal: deal, contact: contact, company: company,
      activity_type: 'demonstration', title: 'Demonstração JRC Conversas',
      due_at: 1.day.from_now, status: 'scheduled',
      description: 'Apresentar atendimento omnichannel, telefonia e CRM para 10 usuários.'
    )
    demonstration.update!(
      status: 'completed', completed_at: Time.current,
      metadata: { 'result' => 'Cliente interessado — enviar proposta.' }
    )

    product = JrcCrm::Product.create!(
      account: account,
      name: 'JRC Conversas — 10 usuários',
      sku: 'JRC-CONV-10',
      product_type: 'license',
      billing_model: 'monthly',
      unit_price_cents: 100_000,
      setup_fee_cents: 120_000,
      minimum_quantity: 1,
      requires_contract: true,
      integrations: %w[contracts implementation],
      activation_days: 30,
      active: true
    )
    proposal = JrcCrm::Proposal.create!(
      account: account,
      deal: deal,
      owner: seller,
      title: 'JRC Conversas — Nexora Tech',
      status: 'sent',
      sent_at: Time.current,
      term_months: 12,
      follow_up_enabled: true,
      follow_up_days: 3
    )
    proposal.proposal_items.create!(
      product: product,
      name_snapshot: product.name,
      description_snapshot: 'Licenças e implantação JRC Conversas',
      quantity: 1,
      unit_price_cents: product.unit_price_cents,
      setup_fee_cents: product.setup_fee_cents,
      billing_model: product.billing_model,
      activation_days: product.activation_days
    )

    proposal.accept_by_customer!(
      name: 'Marcelo Andrade',
      document: 'DOCUMENTO-DE-TESTE',
      remote_ip: '127.0.0.1',
      user_agent: 'RSpec'
    )
    lifecycle = JrcCrm::AcceptedProposalLifecycleService.new(proposal: proposal.reload, actor: seller).call

    expect(lifecycle[:success]).to be(true)
    order = lifecycle[:order]
    expect(deal.reload).to be_won
    expect(company.reload.relationship_type).to eq('customer')
    expect(contact.reload.company_id).to eq(company.id)
    expect(proposal.sales_orders.count).to eq(1)
    expect(order.deal_id).to eq(deal.id)
    expect(order.contact_id).to eq(contact.id)
    expect(order.snapshot['generate_contract']).to be(true)
    expect(order.snapshot['send_to_implementation']).to be(true)
    expect(order.snapshot['create_implementation_project']).to be(true)

    # Replaying the accepted proposal repairs/reuses downstream records instead
    # of duplicating the sale.
    replay = JrcCrm::AcceptedProposalLifecycleService.new(proposal: proposal.reload, actor: seller).call
    expect(replay[:order].id).to eq(order.id)
    expect(proposal.sales_orders.count).to eq(1)

    order.update!(status: 'approved')
    JrcCrm::OrderWorkflowSyncService.new(order: order.reload, actor: seller).call

    expect(order.contracts.count).to eq(1)
    contract = order.contracts.first
    expect(contract.contact_id).to eq(contact.id)
    expect(contract.deal_id).to eq(deal.id)
    expect(contract.monthly_cents).to eq(order.monthly_cents)

    expect(order.backoffice_requests.where(request_kind: 'fulfillment').count).to eq(1)
    backoffice = order.backoffice_requests.first
    expect(backoffice.contract_id).to eq(contract.id)
    expect(backoffice.metadata['implementation_project_id']).to be_present,
      backoffice.metadata['implementation_project_warning']

    project = JrcProjects::Project.find(backoffice.metadata['implementation_project_id'])
    expect(project.company_id).to eq(company.id)
    expect(project.contact_id).to eq(contact.id)
    expect(project.operation_links.where(crm_deal_id: deal.id)).to exist
    expect(project.tasks.pluck(:title)).to include('Kickoff', 'Configuração', 'Treinamento', 'Go-live')

    # A second workflow replay keeps one contract/backoffice/project.
    JrcCrm::OrderWorkflowSyncService.new(order: order.reload, actor: seller).call
    expect(order.contracts.count).to eq(1)
    expect(order.backoffice_requests.where(request_kind: 'fulfillment').count).to eq(1)
    expect(JrcProjects::Project.where(account_id: account.id, idempotency_key: "crm-order-implementation-#{order.id}").count).to eq(1)

    # The operational handoff remains explicit: contract signature and the
    # implementation checklist are real gates and are not auto-completed.
    contract.update!(
      status: 'active', signature_status: 'signed', signature_mode: 'manual',
      signed_by_name: 'Marcelo Andrade', signed_at: Time.current
    )
    backoffice.advance! # analysis -> contract
    expect(backoffice.reload.stage).to eq('contract')
    backoffice.advance! # contract -> implementation
    expect(backoffice.reload.stage).to eq('implementation')

    operational_metadata = backoffice.metadata.deep_dup
    operational_metadata['implementation_checklist'] = Array(operational_metadata['implementation_checklist']).map do |item|
      item.merge('done' => true)
    end
    operational_metadata['payment_required_before_completion'] = true
    backoffice.update!(metadata: operational_metadata)
    backoffice.advance! # implementation -> finance
    expect(backoffice.reload.stage).to eq('finance')

    invoice = JrcCrm::Invoice.create!(
      account: account, sales_order: order, contract: contract, contact: contact,
      status: 'issued', issued_on: Date.current, due_on: 10.days.from_now.to_date,
      subtotal_cents: order.total_cents, total_cents: order.total_cents,
      balance_cents: order.total_cents, snapshot: { 'source' => 'nexora_end_to_end' }
    )
    JrcCrm::Payment.create!(
      account: account, invoice: invoice, amount_cents: invoice.total_cents,
      paid_at: Time.current, method: 'pix', reconciliation_status: 'reconciled',
      metadata: { 'source' => 'nexora_end_to_end' }
    )
    invoice.recalculate_balance!
    expect(invoice.reload).to be_paid

    JrcCrm::OrderWorkflowSyncService.new(order: order.reload, actor: seller, event: 'payment_received').call
    expect(backoffice.reload).to be_completed

    # The Customer 360 must still point to the same master company/contact and
    # expose the complete commercial/operational history of the sale.
    account_user = account.account_users.find_by!(user_id: seller.id)
    customer360 = JrcCustomers::Customer360.new(
      account: account, user: seller, account_user: account_user, company: company.reload
    )
    sources = customer360.sources
    overview = customer360.overview
    expect(sources['leads']).to include(lead)
    expect(sources['deals']).to include(deal)
    expect(sources['proposals']).to include(proposal)
    expect(sources['orders']).to include(order)
    expect(sources['contracts']).to include(contract)
    expect(sources['projects']).to include(project)
    expect(sources['activities']).to include(demonstration)
    expect(overview[:contracts_active]).to eq(1)
    expect(overview[:contracts_mrr_cents]).to eq(order.monthly_cents)
    expect(overview[:projects_active]).to eq(1)
  end
end

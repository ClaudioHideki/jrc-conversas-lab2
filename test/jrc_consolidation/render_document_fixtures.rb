# Production PDF services + production calculator, with synthetic records.
# This exercises rendering, NOT ActiveRecord/controllers or a production database.
require 'fileutils'
require 'ostruct'
require 'json'
ROOT = File.expand_path('../..', __dir__)
%w[commercial_financials order_financials commercial_pdf/font_metrics commercial_pdf/logo
   commercial_pdf/document commercial_pdf/layout document_branding commercial_document_service
   proposal_pdf_service order_pdf_service contract_pdf_service].each do |name|
  require File.join(ROOT, "app/services/jrc_crm/#{name}")
end
OUT = ARGV[0] || File.join(ROOT, 'tmp', 'jrc_document_fixtures')
FileUtils.mkdir_p(OUT)
class SyntheticRecord < OpenStruct
  def attributes
    to_h
  end
end

class DocumentFixtures
  def self.render(kind, count, long: false, customer: 'Cliente Demonstracao JRC')
    raw = (1..count).map do |i|
      { product_id: i, name: "ITEM-#{i.to_s.rjust(3, '0')} Servico comercial de atendimento",
        quantity: 2, unit_cents: 10000 + i * 123, discount_cents: 123,
        snapshot: { billing_model: i.even? ? 'monthly' : 'one_time', setup_fee_cents: 500,
          description: long ? ('Escopo tecnico completo sem corte de descricao e com caracteres (A/B) e \\ referencia. ' * 170) + 'MARCADOR-FINAL-DESCRICAO' : "Configuracao de canais e suporte tecnico. Escopo exclusivo do item #{i}.",
          unit_name: 'licenca', activation_days: 3, validation_period_days: 7,
          included_quantity: 25, included_unit: 'chamadas' } }
    end
    attrs = { shipping_mode: 'separate', shipping_in_installments: false, shipping_cents: count.positive? ? 12345 : 0,
      payment_condition: 'down_payment_installments', down_payment_cents: count.positive? ? 5000 : 0,
      installments_count: 7, payment_method: 'boleto', has_monthly_fee: true,
      discount_cents: count.positive? ? 321 : 0, first_due_date: '2026-09-30' }
    terms = JrcCrm::CommercialFinancials.new(attributes: attrs, items: raw).call
    contact = SyntheticRecord.new(name: customer, email: 'cliente@example.invalid', phone_number: '(11) 0000-0000')
    owner = SyntheticRecord.new(name: 'Equipe Comercial JRC')
    proposal = SyntheticRecord.new(title: 'Solucao integrada para atendimento e relacionamento', proposal_number: "PRP-TESTE-#{count}",
      version_number: 2, financial_items: raw, financial_summary: terms, customer_contact: contact,
      owner: owner, term_months: 12, status: 'accepted', accepted_by_name: customer,
      accepted_at: Date.new(2026, 9, 29), valid_until: Date.new(2026, 10, 15),
      issuer_company_name: 'Grupo JRC', solution_description: 'Documento sintetico para validar o gerador JRC. Nao representa uma proposta real.',
      commercial_notes: 'Valores em reais. Escopo e condicoes descritos nos itens.',
      next_steps: "1. Aprovacao comercial\n2. Implantacao e validacao\n3. Inicio da operacao", billing_day: 30,
      first_billing_days: 1, taxes_included: true, renewal_type: 'manual', annual_adjustment_index: 'IPCA', cancellation_penalty_percent: 0)
    snapshot = JrcCrm::OrderFinancials.snapshot_for(terms, 'company_name' => 'JRC Conversas', 'activation_date' => '2026-10-01')
    order = SyntheticRecord.new(JrcCrm::OrderFinancials.attributes_for(terms).merge(
      snapshot: snapshot, order_number: "PED-TESTE-#{count}", financial_summary: terms, contact: contact, owner: owner,
      order_items: terms[:items].map { |item| SyntheticRecord.new(item) }, proposal: proposal, status: 'approved',
      notes: 'Pedido ficticio utilizado exclusivamente na verificacao do documento.'))
    contract = SyntheticRecord.new(contract_number: "CTR-TESTE-#{count}", sales_order: order, contact: contact,
      owner: owner, financial_summary: terms, one_time_cents: terms[:total_cents], monthly_cents: terms[:monthly_cents],
      contract_items: terms[:items].map { |item| SyntheticRecord.new(item.merge(monthly_cents: item[:recurring_cents])) },
      starts_on: Date.new(2026, 10, 1), ends_on: Date.new(2027, 9, 30), status: 'draft', signature_status: 'not_started',
      renewal_type: 'manual', adjustment_index: 'IPCA',
      content_override: (1..20).map { |i| "CLAUSULA-#{i.to_s.rjust(3, '0')} Texto de teste para verificar a preservacao integral de condicoes comerciais e operacionais. Todos os itens do documento devem permanecer disponiveis." }.join("\n\n"),
      lifecycle_metadata: { 'addenda' => [{ 'title' => 'Aditivo de teste', 'notes' => 'ADITIVO-FINAL preservado no documento.', 'created_at' => '2026-09-29' }] })
    record, service = { proposal: [proposal, JrcCrm::ProposalPdfService], order: [order, JrcCrm::OrderPdfService], contract: [contract, JrcCrm::ContractPdfService] }.fetch(kind)
    bytes = service.new(record).call
    basename = "#{kind}_#{count}#{long ? '_long' : ''}#{customer.include?('GoPure') ? '_client_data' : ''}.pdf"
    File.binwrite(File.join(OUT, basename), bytes)
    { file: basename, items: count, kind: kind, total_cents: terms[:total_cents], monthly_cents: terms[:monthly_cents], long: long, customer: customer }
  end
end
rows = []
[:proposal, :order, :contract].each { |kind| [0, 7, 8, 37].each { |count| rows << DocumentFixtures.render(kind, count) } }
rows << DocumentFixtures.render(:order, 1, long: true)
rows << DocumentFixtures.render(:proposal, 1, customer: 'GoPure - cliente legitimo')
File.write(File.join(OUT, 'fixtures.json'), JSON.pretty_generate(rows))
puts JSON.pretty_generate(directory: OUT, files: rows.length, engine: 'production PDF services, synthetic records')

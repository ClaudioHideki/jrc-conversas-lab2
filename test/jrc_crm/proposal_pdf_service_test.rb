# Run directly with bundle exec ruby; deliberately never load Rails/test_helper.
require 'minitest/autorun'
require 'active_support/all'
require 'action_controller'
require 'pathname'
require 'logger'
require 'ostruct'
require_relative '../../app/services/jrc_crm/proposal_pdf_service'

# Only the filesystem/logger services used by the PDF renderer; no application boot.
module Rails
  def self.root
    Pathname.new(File.expand_path('../..', __dir__))
  end

  def self.logger
    Logger.new($stderr)
  end
end

class ProposalPdfServiceTest < Minitest::Test
  def setup
    @item = OpenStruct.new(name_snapshot: 'Telefonia JRC', description_snapshot: 'Atendimento integrado',
                           included_quantity: 10, included_unit: 'minutos', billing_model: 'monthly', quantity: 2,
                           unit_price_cents: 10_000, setup_fee_cents: 5000, applied_discount_cents: 1000, initial_total_cents: 24_000)
    @proposal = OpenStruct.new(deal: OpenStruct.new(title: 'Negócio'), customer_contact: OpenStruct.new(name: 'Cliente exemplo'),
                               title: 'Atendimento e relacionamento', proposal_number: 'JRC-123', version_number: 3,
                               solution_description: 'Solução integrada JRC.', term_months: 12, valid_until: Date.new(2026, 10, 10),
                               monthly_cents: 19_000, implementation_cents: 5000, item_discount_cents: 1000,
                               effective_general_discount_cents: 2000, total_cents: 22_000, payment_method: 'Boleto', billing_day: 10,
                               annual_adjustment_index: 'IPCA', renewal_type: 'automatic', cancellation_penalty_percent: 10,
                               commercial_notes: 'Observações salvas.', next_steps: 'Próximo passo salvo: reunião técnica.',
                               proposal_items: [@item])
    @proposal.define_singleton_method(:taxes_included?) { true }
  end

  def render_proposal(filename = nil)
    service = JrcCrm::ProposalPdfService.new(@proposal)
    pdf = service.call
    @pages = service.instance_variable_get(:@pages).map { |page| page.commands.dup.force_encoding('Windows-1252').encode('UTF-8') }
    File.binwrite(File.join(ENV['PDF_QA_OUTPUT'], filename), pdf) if filename && ENV['PDF_QA_OUTPUT']
    [pdf, @pages.join("\n")]
  end

  def test_small_proposal_preserves_branding_discounts_and_saved_conditions
    pdf, text = render_proposal('few-products.pdf')
    assert_equal 3, @pages.length
    assert_page_structure
    ['JRC Conversas', 'VERSÃO 3', 'Descontos nos itens', 'Desconto comercial adicional', 'Vencimento: 10',
     'Impostos: inclusos', 'Reajuste: IPCA', 'Renovação: automática', 'Multa de cancelamento', 'reunião técnica.'].each do |value|
      assert_includes text, value
    end
    assert_includes pdf, '/Subtype /Image'
    assert_includes File.read(Rails.root.join('app/services/jrc_crm/proposal_pdf_service.rb')), "'logo-jrc.png'"
    assert_nil(/gopure|suplementos premium/i.match(text))
  end

  def test_many_products_long_descriptions_notes_and_page_boundaries
    @proposal.proposal_items = (1..35).map { |number| @item.dup.tap { |item| item.name_snapshot = "Produto #{number}" } }
    @proposal.proposal_items[0].description_snapshot = "#{'Descrição extensa WMWM ' * 180}FIM-DESCRICAO"
    @proposal.solution_description = "#{'Escopo detalhado. ' * 130}FIM-SOLUCAO"
    @proposal.commercial_notes = "#{'Observação comercial extensa. ' * 230}FIM-OBSERVACOES"
    @proposal.next_steps = "#{'Próximo passo salvo. ' * 100}FIM-PASSOS"
    _, text = render_proposal('many-products.pdf')
    assert_operator @pages.length, :>, 6
    %w[FIM-DESCRICAO FIM-SOLUCAO FIM-OBSERVACOES FIM-PASSOS].each { |value| assert_includes text, value }
    (1..35).each { |number| assert_includes text, "(Produto #{number})" }
    assert_page_structure
  end

  def assert_page_structure
    @pages.each_with_index do |page, index|
      assert_includes page, "Página #{index + 1} de #{@pages.length}"
      assert_includes page, '/Logo Do'
      assert_includes page, 'Produto / Serviço' if page.include?('(Produto ') || page.include?('produtos (continuação)')
      assert_page_bounds(page)
    end
  end

  def assert_page_bounds(page)
    page.scan(%r{BT /F[12] ([\d.]+) Tf ([\d.]+) ([\d.-]+) Td \((.*?)\) Tj ET}).each do |size, x, y, value|
      assert_operator x.to_f, :>=, 48
      assert_operator y.to_f, :>=, 40
      assert_operator y.to_f, :<=, 790
      next if y == '40' || y == '790'

      assert_operator y.to_f - (size.to_f * 0.25), :>, 76, value
      assert_operator y.to_f + size.to_f, :<, 770, value
    end
  end

  def test_long_unbroken_words_and_wide_glyphs_fit_columns
    text = "#{'W' * 150} #{'á' * 150}"
    lines = JrcCrm::ProposalPdfService::Page.wrap(text, width: 142, size: 7)
    assert_equal text.delete(' '), lines.join
    lines.each { |line| assert_operator JrcCrm::ProposalPdfService::Page.text_width(line, 7), :<=, 142 }
  end

  def test_empty_products_and_long_title_customer_and_terms
    @proposal.proposal_items = []
    @proposal.title = 'Título extenso ' * 120
    @proposal.customer_contact.name = 'Cliente extenso ' * 100
    @proposal.payment_method = 'Condição comercial salva ' * 200
    _, text = render_proposal
    assert_includes text, 'Nenhum produto adicionado.'
    assert_operator @pages.length, :>, 3
    @pages.each { |page| assert_includes page, 'Página' }
  end
end

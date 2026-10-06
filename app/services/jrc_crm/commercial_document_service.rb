require 'bigdecimal'
require 'date'

module JrcCrm
  # Shared presentation only; existing Proposal/Order/Contract domain and APIs
  # remain the authorities for permissions, data and the frozen financial terms.
  class CommercialDocumentService
    TITLES = { proposal: 'Proposta comercial', order: 'Pedido comercial', contract: 'Contrato comercial' }.freeze
    BILLING = { 'one_time' => 'Única', 'monthly' => 'Mensal', 'annual' => 'Anual', 'usage' => 'Por uso' }.freeze
    PAYMENTS = { 'cash' => 'À vista', 'installments' => 'Parcelas sem entrada', 'down_payment_installments' => 'Entrada + parcelas' }.freeze
    SHIPPING = { 'included' => 'Incluso', 'separate' => 'Cobrado separadamente', 'not_applicable' => 'Sem frete' }.freeze
    RENEWALS = { 'automatic' => 'Automática', 'manual' => 'Manual', 'none' => 'Sem renovação' }.freeze

    def initialize(kind:, record:)
      @kind, @record = kind.to_sym, record
      raise ArgumentError, 'Tipo de documento invalido.' unless TITLES.key?(@kind)
      @order = @kind == :contract ? value(record, :sales_order) : (@kind == :order ? record : nil)
      @snapshot = CommercialFinancials.symbolize(value(@order, :snapshot, {}))
      @financials = CommercialFinancials.symbolize(record.financial_summary)
      @contact = @kind == :proposal ? value(record, :customer_contact) : value(record, :contact)
      @contact ||= value(@order, :contact)
    end

    def call
      number = value(@record, { proposal: :proposal_number, order: :order_number, contract: :contract_number }.fetch(@kind))
      @layout = CommercialPdf::Layout.new(title: TITLES.fetch(@kind), number: number, logo: DocumentBranding.logo)
      title = value(@record, :title)
      @layout.heading(title) if present?(title)
      identity
      if @kind == :proposal
        @layout.section('Descrição da solução')
        @layout.paragraph(value(@record, :solution_description, 'Escopo conforme os itens e as condições abaixo.'))
      end
      items
      financial_terms
      case @kind
      when :proposal then proposal_terms
      when :order then order_terms
      when :contract then contract_terms
      end
      @layout.render
    end

    private

    def value(record, name, fallback = nil)
      result = record.public_send(name) if record && record.respond_to?(name)
      result.nil? || result.to_s.empty? ? fallback : result
    end

    def present?(text)
      !text.nil? && !text.to_s.strip.empty?
    end

    def customer_name
      value(value(@record, :customer_company), :name) || value(@contact, :name) || @snapshot[:customer_name] || value(value(@record, :deal), :title) || 'Cliente'
    end

    def issuer
      # This is business data, NOT the product brand. Legitimate client/legal
      # entity names are preserved; no blind replacement of business records.
      value(@record, :issuer_company_name) || value(value(@order, :business_unit), :name) || @snapshot[:company_name] || DocumentBranding::NAME
    end

    def identity
      rows = [['Cliente / contratante', customer_name], ['Responsável comercial', value(value(@record, :owner), :name, 'Equipe JRC')],
              ['Emissor informado', issuer]]
      rows << ['Contato', [value(@contact, :email), value(@contact, :phone_number)].compact.join(' | ')] if value(@contact, :email) || value(@contact, :phone_number)
      if @kind == :proposal
        rows += [['Validade', date(value(@record, :valid_until))], ['Versão', value(@record, :version_number, 1).to_s],
                 ['Vigência', "#{value(@record, :term_months)} meses"]]
        rows << ['Documento do emissor', value(@record, :issuer_tax_id)] if present?(value(@record, :issuer_tax_id))
        rows << ['Unidade emissora', value(@record, :issuer_unit)] if present?(value(@record, :issuer_unit))
      else
        rows << ['Proposta de origem', value(value(@order, :proposal), :proposal_number, 'Pedido direto')]
        rows << ['Pedido de origem', value(@order, :order_number)] if @kind == :contract
        rows << ['Situação', value(@record, :status, 'A definir')]
      end
      @layout.key_values(rows)
    end

    def item_records
      if @kind == :proposal
        @record.financial_items
      elsif @kind == :contract
        records = value(@record, :contract_items, []).to_a
        records.empty? ? value(@order, :order_items, []).to_a : records
      else
        value(@record, :order_items, []).to_a
      end
    end

    def items
      @layout.section('Produtos e serviços')
      rows = item_records.each_with_index.map do |record, index|
        raw = CommercialFinancials.symbolize(record.respond_to?(:attributes) ? record.attributes : record.to_h)
        snap = CommercialFinancials.symbolize(raw[:snapshot] || {})
        normalized = if @kind == :proposal
                       CommercialFinancials.new(attributes: @financials, items: []).normalize_item(raw)
                     else raw
                     end
        name = raw[:name] || raw[:name_snapshot] || 'Item'
        description = raw[:description_snapshot] || snap[:description]
        details = ["#{index + 1}. #{name}"]
        details << description if present?(description)
        billing = snap[:billing_model] || raw[:billing_model] || 'one_time'
        details << "Cobrança: #{BILLING.fetch(billing, billing)} | Unidade: #{snap[:unit_name] || 'unidade'}"
        unit = raw[:unit_cents] || raw[:unit_price_cents] || snap[:unit_cents]
        details << "Preço unitário: #{money(unit)}" unless unit.nil?
        setup = snap[:setup_fee_cents] || raw[:setup_fee_cents]
        details << "Implantação: #{money(setup)}" if setup.to_i.positive?
        discount = raw[:discount_cents] || snap[:discount_cents]
        details << "Desconto no item: #{money(discount)}" if discount.to_i.positive?
        if snap[:included_quantity].to_f.positive?
          details << "Franquia: #{quantity(snap[:included_quantity])} #{snap[:included_unit]}"
        end
        details << "Excedente por unidade: #{money(snap[:overage_unit_price_cents])}" if snap[:overage_unit_price_cents].to_i.positive?
        details << "Ativação: #{snap[:activation_days]} dias" if snap[:activation_days].to_i.positive?
        details << "Validação: #{snap[:validation_period_days]} dias" if snap[:validation_period_days].to_i.positive?
        recurring = normalized[:recurring_cents] || normalized[:monthly_cents] || 0
        recurring = 0 unless @financials[:has_monthly_fee]
        [details.join("\n"), quantity(raw[:quantity]), money(normalized[:one_time_cents]), money(recurring)]
      end
      if rows.empty?
        @layout.paragraph('Sem itens discriminados. Consulte os valores e o escopo informado.')
      else
        @layout.table(rows, widths: [266, 38, 101, CommercialPdf::Layout::WIDTH - 405],
          headers: ['Item / escopo', 'Qtd.', 'Total inicial', 'Equiv. mensal'])
      end
    end

    def financial_terms
      f = @financials
      @layout.section('Resumo financeiro')
      @layout.key_values([
        ['Subtotal bruto dos itens', money(f[:subtotal_cents])], ['Desconto nos itens', money(f[:item_discount_cents])],
        ['Desconto comercial', money(f[:discount_cents])], ["Frete - #{SHIPPING.fetch(f[:shipping_mode], f[:shipping_mode].to_s)}", money(f[:shipping_cents])],
        ['Impostos adicionados', money(f[:taxes_cents])], ['TOTAL INICIAL', money(f[:total_cents])],
        ['Recorrência mensal equivalente', f[:has_monthly_fee] ? money(f[:monthly_cents]) : 'Nao contratada'],
        ['Condição comercial', PAYMENTS.fetch(f[:payment_condition], f[:payment_condition].to_s)],
        ['Meio de pagamento', f[:payment_method] || 'A definir'], ['Entrada', money(f[:down_payment_cents])],
        ['Frete fora das parcelas', money(f[:upfront_shipping_cents])], ['Saldo após entrada', money(f[:balance_cents])]
      ])
      @layout.paragraph('A recorrencia futura e apresentada separadamente. Nos itens de cobranca mensal ou anual, o primeiro periodo compoe o total inicial. Valores anuais sao mostrados tambem pelo equivalente mensal.', size: 9, color: CommercialPdf::Layout::MUTED)
      if f[:payment_method].to_s == 'boleto'
        @layout.paragraph('Boleto identifica a condicao comercial. Este documento nao e um boleto bancario nem comprova sua emissao.', size: 9, color: CommercialPdf::Layout::MUTED)
      end
      @layout.section('Plano de pagamento do valor inicial')
      rows = Array(f[:payments]).map do |payment|
        label = case payment[:kind]
                when 'cash' then 'Pagamento a vista'
                when 'down_payment' then 'Entrada'
                when 'shipping' then 'Frete separado'
                else "Parcela #{payment[:number]} de #{f[:installments_count]}"
                end
        [label, date(payment[:date]), money(payment[:value])]
      end
      @layout.table(rows, widths: [240, 125, CommercialPdf::Layout::WIDTH - 365], headers: ['Pagamento', 'Vencimento', 'Valor'])
    end

    def proposal_terms
      @layout.section('Condições comerciais')
      @layout.key_values([
        ['Dia de vencimento', value(@record, :billing_day, 'A definir')],
        ['Primeiro faturamento', "#{value(@record, :first_billing_days, 0)} dias, conforme contratacao"],
        ['Impostos nos valores dos itens', value(@record, :taxes_included) == false ? 'Nao inclusos' : 'Inclusos'],
        ['Reajuste anual', value(@record, :annual_adjustment_index, 'A definir')],
        ['Renovação', RENEWALS.fetch(value(@record, :renewal_type), 'A definir')],
        ['Multa de cancelamento', "#{value(@record, :cancellation_penalty_percent, 0)}%"]
      ])
      text_section('Observações comerciais', value(@record, :commercial_notes))
      text_section('Próximos passos', value(@record, :next_steps))
      if value(@record, :status) == 'accepted'
        @layout.section('Aceite registrado')
        @layout.key_values([['Signatario', value(@record, :accepted_by_name, 'A definir')], ['Data', date(value(@record, :accepted_at))]])
      end
    end

    def order_terms
      @layout.section('Implantacao e entrega')
      @layout.key_values([['Previsao de ativacao', date(@snapshot[:activation_date])],
        ['Responsavel interno', @snapshot[:operation_owner_name] || value(value(@record, :owner), :name, 'A definir')],
        ['Equipe', @snapshot[:implementation_team] || 'A definir'], ['Prioridade', @snapshot[:priority] || 'Normal']])
      text_section('Observacoes', value(@record, :notes))
      text_section('Observacoes financeiras', @snapshot[:financial_notes])
      @layout.signature_rows(customer_name, issuer)
    end

    def contract_terms
      @layout.section('Vigência e renovacao')
      @layout.key_values([['Vigência', validity], ['Renovação', RENEWALS.fetch(value(@record, :renewal_type), 'A definir')],
        ['Indice de reajuste', value(@record, :adjustment_index, 'IPCA')], ['Situação da assinatura', value(@record, :signature_status, 'A definir')]])
      @layout.section('Condicoes contratuais')
      clauses.each_with_index { |clause, index| @layout.paragraph("#{index + 1}. #{clause}") }
      meta = CommercialFinancials.symbolize(value(@record, :lifecycle_metadata, {}))
      Array(meta[:addenda]).each_with_index do |entry, index|
        @layout.section("Aditivo #{index + 1}")
        @layout.paragraph(entry[:title])
        @layout.paragraph(entry[:notes])
        @layout.paragraph("Registrado em #{date(entry[:created_at])}", size: 9)
      end
      @layout.signature_rows(customer_name, issuer)
    end

    def clauses
      override = value(@record, :content_override)
      return paragraphs(override) if present?(override)
      template = value(@record, :contract_template)
      if present?(value(template, :body))
        context = { 'cliente' => { 'nome' => customer_name }, 'contrato' => { 'numero' => value(@record, :contract_number) },
          'pedido' => { 'numero' => value(@order, :order_number) }, 'vigencia' => validity,
          'valor_mensal' => money(@financials[:monthly_cents]), 'valor_total' => money(@financials[:total_cents]) }
        return paragraphs(Liquid::Template.parse(template.body).render(context))
      end
      ["Este contrato formaliza a contratacao vinculada ao pedido #{value(@order, :order_number)}.",
       "Vigência: #{validity}. Os valores iniciais e a recorrencia seguem o resumo financeiro deste documento.",
       "Os reajustes seguem o indice #{value(@record, :adjustment_index, 'IPCA')}. A renovacao e #{RENEWALS.fetch(value(@record, :renewal_type), 'manual')}.",
       value(@record, :notes, 'As partes declaram ciencia das condicoes comerciais e operacionais descritas. Alteracoes devem ser formalizadas entre as partes.')]
    end

    def paragraphs(text)
      text.to_s.split(/\n{2,}/).map(&:strip).reject(&:empty?)
    end

    def text_section(title, text)
      return unless present?(text)
      @layout.section(title)
      @layout.paragraph(text)
    end

    def validity
      "#{date(value(@record, :starts_on))} a #{date(value(@record, :ends_on))}"
    end

    def date(raw)
      return 'A definir' unless present?(raw)
      return raw.strftime('%d/%m/%Y') if raw.respond_to?(:strftime)
      Date.iso8601(raw.to_s[0, 10]).strftime('%d/%m/%Y')
    rescue Date::Error
      raw.to_s
    end

    def quantity(value)
      text = BigDecimal((value || 0).to_s).to_s('F')
      text.sub(/\.0+$/, '').sub(/(\.\d*?)0+$/, '\\1').tr('.', ',')
    end

    def money(cents)
      sign = cents.to_i.negative? ? '-' : ''
      integer, fraction = cents.to_i.abs.divmod(100)
      "#{sign}R$ #{integer.to_s.reverse.scan(/.{1,3}/).join('.').reverse},#{fraction.to_s.rjust(2, '0')}"
    end
  end
end

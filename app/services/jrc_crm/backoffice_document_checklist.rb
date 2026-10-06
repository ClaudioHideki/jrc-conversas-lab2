module JrcCrm
  class BackofficeDocumentChecklist
    SOURCES = %w[contract_generated contract_signed customer_registration billing_registration technical_owner financial_owner implementation_info manual].freeze
    LABELS = { 'contract_generated' => 'Contrato gerado', 'contract_signed' => 'Contrato assinado',
      'customer_registration' => 'Cadastro do cliente', 'billing_registration' => 'Dados de faturamento',
      'technical_owner' => 'Responsável técnico', 'financial_owner' => 'Responsável financeiro',
      'implementation_info' => 'Dados de implantação' }.freeze

    def initialize(request:, actor: nil)
      @request, @actor, @order = request, actor, request.sales_order
    end

    def sync!
      @request.with_lock do
        data = (@request.metadata || {}).deep_dup
        configured = @order.order_items.includes(:product).flat_map do |item|
          Array(item.product&.document_rules).map { |row| row.merge('product_id' => item.product_id) }
        end
        if OrderContractService.new(order: @order).required?
          configured += %w[contract_generated contract_signed].map { |source| { 'key' => source, 'source' => source, 'label' => LABELS[source], 'required' => true, 'blocking' => true } }
        end
        data['document_checklist'] = configured.uniq { |row| row['key'] }.map do |row|
          if row['source'] == 'manual'
            row.merge('status' => data.dig('document_statuses', row['key']) || 'pending')
          else
            evidence = source_evidence(row['source'])
            row.merge('status' => evidence ? 'approved' : 'pending', 'evidence' => evidence)
          end
        end
        data['document_statuses'] ||= {}
        data['document_checklist'].each { |row| data['document_statuses'][row['key']] = row['status'] }
        data['contract_required'] = OrderContractService.new(order: @order).required?
        data['contract_template_warning'] = @request.contract && !@request.contract.contract_template ? 'Contrato sem modelo: selecione um modelo ativo antes da geração do PDF.' : nil
        return @request if data == @request.metadata
        before = @request.metadata
        @request.update!(metadata: data)
        AuditEvent.create!(account_id: @order.account_id, actor_type: 'User', actor_id: @actor&.id,
          event_type: 'backoffice_updated', resource_type: 'JrcCrm::BackofficeRequest', resource_id: @request.id,
          from_value: { document_checklist: before['document_checklist'] },
          to_value: { document_checklist: data['document_checklist'] }, metadata: { source: 'native_document_reconciliation' })
      end
      @request
    end

    private

    def source_evidence(source)
      contract = @request.contract
      contact = @order.contact
      snapshot = (@order.snapshot || {}).with_indifferent_access
      case source
      when 'contract_generated' then { contract_id: contract.id } if contract&.contract_template || contract&.content_override.present?
      when 'contract_signed' then { contract_id: contract.id, document_id: contract.signed_document.id, signed_at: contract.signed_at } if contract&.signature_status == 'signed' && contract.signed_document.attached?
      when 'customer_registration' then { contact_id: contact.id, company_id: contact.company_id } if contact && contact.name.present? && (contact.identifier.present? || contact.company&.tax_id.present?)
      when 'billing_registration' then { order_id: @order.id } if @order.payment_condition.present? && contact&.email.present?
      when 'technical_owner' then { order_id: @order.id, value: snapshot[:operation_owner_name] } if snapshot[:operation_owner_name].present?
      when 'financial_owner' then { order_id: @order.id, value: snapshot[:customer_owner_name] } if snapshot[:customer_owner_name].present?
      when 'implementation_info' then { order_id: @order.id, activation_date: snapshot[:activation_date] } if snapshot[:activation_date].present? && snapshot[:implementation_team].present?
      end
    end
  end
end

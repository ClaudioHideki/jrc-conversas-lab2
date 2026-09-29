module Api::V1::Accounts::Crm
  class ContractsController < BaseController
    before_action :set_contract, only: %i[show update pdf history upload_documents download_document download_signed_document prepare_signature send_for_signature register_manual_signature renew addendum]

    def index
      rows = visible_to_current_user(crm_scope.jrc_crm_contracts)
             .includes(:contact, :owner, :sales_order, :deal, :contract_template, documents_attachments: :blob)
             .order(created_at: :desc)
      render json: rows.map { |contract| serialize(contract) }
    end

    def show
      render json: serialize(@contract, include_history: true)
    end

    def create
      order = visible_to_current_user(crm_scope.jrc_crm_sales_orders).find(params.dig(:contract, :sales_order_id))
      attributes = normalized_contract_params
      contract = nil
      order.with_lock do
        contract = crm_scope.jrc_crm_contracts.create!(attributes.merge(
          deal: order.deal, contact: order.contact, owner: order.owner, business_unit: order.business_unit
        ))
        copy_items!(order, contract)
        order.backoffice_requests.where(request_kind: 'fulfillment').update_all(contract_id: contract.id, updated_at: Time.current)
        audit!(contract, 'contract_created', {}, audit_snapshot(contract))
      end
      render json: serialize(contract.reload), status: :created
    end

    def update
      @contract.with_lock do
        before = audit_snapshot(@contract)
        attributes = normalized_contract_params
        if attributes.key?('lifecycle_metadata')
          attributes['lifecycle_metadata'] = (@contract.lifecycle_metadata || {}).deep_merge(attributes['lifecycle_metadata'])
        end
        @contract.update!(attributes)
        sync_signature_status_from_contract_status!(@contract)
        sync_order_after_signature!(@contract)
        audit!(@contract, 'contract_updated', before, audit_snapshot(@contract))
      end
      render json: serialize(@contract.reload)
    end

    def pdf
      pdf_data = JrcCrm::ContractPdfService.new(@contract).call
      send_data pdf_data,
                filename: "#{@contract.contract_number.parameterize.presence || "contrato-#{@contract.id}"}.pdf",
                type: 'application/pdf',
                disposition: params[:download].present? ? 'attachment' : 'inline'
    end

    def history
      render json: history_rows(@contract)
    end

    def upload_documents
      uploads = Array(params[:files]).compact
      return render json: { message: 'Selecione ao menos um documento.' }, status: :unprocessable_entity if uploads.empty?
      if @contract.documents.count + uploads.length > 10 || uploads.any? { |file| file.size > 20.megabytes }
        return render json: { message: 'Limite de 10 arquivos de ate 20 MB por contrato.' }, status: :unprocessable_entity
      end
      uploads.each { |file| @contract.documents.attach(file) }
      audit!(@contract, 'contract_document_uploaded', {}, { filenames: uploads.map(&:original_filename) })
      render json: { documents: document_rows(@contract.reload) }, status: :created
    end

    def download_document
      attachment = @contract.documents.find(params[:attachment_id])
      send_data attachment.blob.download, filename: attachment.filename.to_s,
                type: attachment.content_type, disposition: 'attachment'
    end

    def download_signed_document
      unless @contract.signed_document.attached?
        return render json: { message: 'Este contrato não possui documento assinado anexado.' }, status: :not_found
      end

      attachment = @contract.signed_document
      send_data attachment.blob.download, filename: attachment.filename.to_s,
                type: attachment.content_type, disposition: 'attachment'
    end

    def prepare_signature
      mode = params[:mode].to_s.presence || 'manual'
      unless mode.in?(%w[manual provider])
        return render json: { message: 'Modo de assinatura inválido.' }, status: :unprocessable_entity
      end

      provider = params[:provider].to_s.presence
      if mode == 'provider' && provider.blank?
        return render json: { message: 'Informe o provedor de assinatura. Nenhuma integração externa foi executada.' }, status: :unprocessable_entity
      end

      @contract.update!(signature_mode: mode, signature_provider: provider,
                        signature_status: 'prepared', status: 'awaiting_signature')
      audit!(@contract, 'contract_signature_prepared', {}, { mode: mode, provider: provider })
      render json: serialize(@contract.reload)
    end

    def send_for_signature
      unless @contract.signature_mode == 'provider'
        return render json: { message: 'Este contrato não está configurado para assinatura por provedor.' }, status: :unprocessable_entity
      end

      external_id = params[:external_id].to_s.presence
      unless external_id
        return render json: {
          message: 'Integração externa não configurada/executada. Informe o identificador retornado pelo provedor somente após envio real.'
        }, status: :unprocessable_entity
      end

      @contract.update!(signature_external_id: external_id, signature_status: 'sent', status: 'awaiting_signature')
      audit!(@contract, 'contract_signature_sent', {}, { provider: @contract.signature_provider, external_id: external_id })
      render json: serialize(@contract.reload)
    end

    def register_manual_signature
      signed_name = params[:signed_by_name].to_s.strip
      return render json: { message: 'Informe quem assinou o contrato.' }, status: :unprocessable_entity if signed_name.blank?

      @contract.signed_document.attach(params[:signed_file]) if params[:signed_file].present?
      @contract.update!(signature_mode: 'manual', signature_provider: nil, signature_status: 'signed',
                        signed_by_name: signed_name, signed_at: parse_time(params[:signed_at]) || Time.current, status: 'active')
      sync_order_after_signature!(@contract)
      audit!(@contract, 'contract_manual_signature_registered', {}, { signed_by_name: signed_name, signed_at: @contract.signed_at })
      render json: serialize(@contract.reload)
    end

    def renew
      starts_on = parse_date(params[:starts_on]) || @contract.ends_on&.+(1.day) || Date.current
      term_months = params[:term_months].presence&.to_i || @contract.renewal_term_months.presence || @contract.term_months.presence || 12
      renewed = nil
      JrcCrm::Contract.transaction do
        renewed = crm_scope.jrc_crm_contracts.create!(
          @contract.attributes.slice('sales_order_id', 'deal_id', 'contact_id', 'owner_id', 'business_unit_id',
                                     'contract_template_id', 'contract_type', 'renewal_type', 'adjustment_index',
                                     'monthly_cents', 'one_time_cents', 'payment_condition', 'due_day', 'auto_renew',
                                     'renewal_notice_days', 'renewal_term_months', 'content_override').merge(
            'contract_number' => nil, 'status' => 'draft', 'starts_on' => starts_on,
            'ends_on' => starts_on.advance(months: term_months) - 1.day, 'term_months' => term_months,
            'source_contract_id' => @contract.id,
            'lifecycle_metadata' => { 'kind' => 'renewal', 'source_contract_id' => @contract.id }
          )
        )
        @contract.contract_items.find_each do |item|
          renewed.contract_items.create!(item.attributes.except('id', 'contract_id', 'created_at', 'updated_at'))
        end
        @contract.update!(status: 'renewed')
      end
      audit!(@contract, 'contract_renewed', {}, { renewed_contract_id: renewed.id })
      render json: serialize(renewed.reload), status: :created
    end

    def addendum
      title = params[:title].to_s.strip.presence || 'Aditivo contratual'
      notes = params[:notes].to_s.strip
      data = (@contract.lifecycle_metadata || {}).deep_dup
      data['addenda'] ||= []
      entry = { 'id' => SecureRandom.uuid, 'title' => title, 'notes' => notes,
                'created_at' => Time.current.iso8601, 'created_by_id' => Current.user&.id }
      data['addenda'] << entry
      @contract.update!(lifecycle_metadata: data)
      audit!(@contract, 'contract_addendum_created', {}, entry)
      render json: serialize(@contract.reload)
    end

    private

    def set_contract
      @contract = visible_to_current_user(crm_scope.jrc_crm_contracts).includes(
        :contact, :owner, :deal, :contract_template, :source_contract,
        { sales_order: { order_items: :product } }, { contract_items: :product }, documents_attachments: :blob
      ).find(params[:id])
    end

    def contract_params
      params.require(:contract).permit(
        :sales_order_id, :contract_template_id, :contract_type, :status, :starts_on, :ends_on, :term_months,
        :renewal_type, :adjustment_index, :monthly_cents, :one_time_cents, :next_adjustment_on, :notes,
        :payment_condition, :due_day, :auto_renew, :renewal_notice_days, :renewal_term_months, :content_override,
        lifecycle_metadata: {}
      )
    end

    def normalized_contract_params
      attributes = contract_params.to_h
      if attributes.key?('contract_template_id')
        template_id = attributes.delete('contract_template_id')
        attributes[:contract_template] = template_id.present? ? crm_scope.jrc_crm_contract_templates.find(template_id) : nil
      end
      attributes.delete('sales_order_id') if @contract.present?
      attributes
    end

    def copy_items!(order, contract)
      order.order_items.find_each do |item|
        contract.contract_items.create!(
          product: item.product, name: item.name, quantity: item.quantity,
          one_time_cents: item.one_time_cents, monthly_cents: item.recurring_cents, snapshot: item.snapshot.merge('unit_cents' => item.unit_cents, 'discount_cents' => item.discount_cents)
        )
      end
    end

    def sync_signature_status_from_contract_status!(contract)
      return unless contract.saved_change_to_status?
      if contract.awaiting_signature? && contract.signature_status == 'not_started'
        contract.update_columns(signature_status: 'prepared', signature_mode: contract.signature_mode.presence || 'manual', updated_at: Time.current)
      end
    end

    def sync_order_after_signature!(contract)
      return unless contract.signature_status == 'signed'
      JrcCrm::OrderWorkflowSyncService.new(order: contract.sales_order, actor: Current.user, event: 'contract_signed').call
    end

    def serialize(contract, include_history: false)
      data = {
        id: contract.id, contract_number: contract.contract_number, status: contract.status,
        contract_type: contract.contract_type, starts_on: contract.starts_on, ends_on: contract.ends_on,
        term_months: contract.term_months, renewal_type: contract.renewal_type, adjustment_index: contract.adjustment_index,
        monthly_cents: contract.monthly_cents, one_time_cents: contract.one_time_cents,
        next_adjustment_on: contract.next_adjustment_on, notes: contract.notes, payment_condition: contract.payment_condition,
        due_day: contract.due_day, auto_renew: contract.auto_renew, renewal_notice_days: contract.renewal_notice_days,
        renewal_term_months: contract.renewal_term_months, content_override: contract.content_override,
        signature_status: contract.signature_status, signature_mode: contract.signature_mode,
        signature_provider: contract.signature_provider, signature_external_id: contract.signature_external_id,
        signed_by_name: contract.signed_by_name, signed_at: contract.signed_at,
        lifecycle_metadata: contract.lifecycle_metadata, source_contract_id: contract.source_contract_id,
        financials: contract.financial_summary,
        contact: contract.contact && { id: contract.contact.id, name: contract.contact.name, email: contract.contact.email },
        owner: contract.owner && { id: contract.owner.id, name: contract.owner.name },
        sales_order: contract.sales_order && { id: contract.sales_order.id, order_number: contract.sales_order.order_number,
                                               total_cents: contract.sales_order.total_cents, monthly_cents: contract.sales_order.monthly_cents },
        deal: contract.deal && { id: contract.deal.id, title: contract.deal.title },
        template: contract.contract_template && { id: contract.contract_template.id, name: contract.contract_template.name,
                                                   category: contract.contract_template.category },
        documents: document_rows(contract),
        signed_document: signed_document_row(contract),
        items: contract.contract_items.map { |item| { id: item.id, product_id: item.product_id, name: item.name,
          quantity: item.quantity, one_time_cents: item.one_time_cents, monthly_cents: item.monthly_cents, snapshot: item.snapshot } },
        created_at: contract.created_at, updated_at: contract.updated_at
      }
      data[:history] = history_rows(contract) if include_history
      data
    end

    def document_rows(contract)
      contract.documents.map do |attachment|
        { id: attachment.id, filename: attachment.filename.to_s, content_type: attachment.content_type,
          byte_size: attachment.byte_size, created_at: attachment.created_at }
      end
    end

    def signed_document_row(contract)
      return nil unless contract.signed_document.attached?
      attachment = contract.signed_document
      { id: attachment.id, filename: attachment.filename.to_s, content_type: attachment.content_type,
        byte_size: attachment.byte_size, created_at: attachment.created_at }
    end

    def history_rows(contract)
      JrcCrm::AuditEvent.for_resource('JrcCrm::Contract', contract.id).recent.limit(300).map do |event|
        { id: event.id, event_type: event.event_type, from_value: event.from_value, to_value: event.to_value,
          metadata: event.metadata, actor_id: event.actor_id, created_at: event.created_at }
      end
    end

    def audit_snapshot(contract)
      { status: contract.status, signature_status: contract.signature_status, starts_on: contract.starts_on,
        ends_on: contract.ends_on, monthly_cents: contract.monthly_cents, one_time_cents: contract.one_time_cents }
    end

    def audit!(contract, event_type, from_value, to_value)
      JrcCrm::AuditEvent.create!(account_id: crm_scope.id, actor_type: 'User', actor_id: Current.user&.id,
        event_type: event_type, resource_type: 'JrcCrm::Contract', resource_id: contract.id,
        from_value: from_value, to_value: to_value, metadata: { source: 'crm_contracts' })
    end

    def parse_date(value)
      Date.iso8601(value.to_s) if value.present?
    rescue ArgumentError
      nil
    end

    def parse_time(value)
      Time.zone.parse(value.to_s) if value.present?
    rescue ArgumentError
      nil
    end
  end
end

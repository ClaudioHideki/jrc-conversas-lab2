module Api::V1::Accounts::Crm
  class BackofficeRequestsController < BaseController
    before_action :set_request, only: %i[show update advance upload_documents download_document document_status add_issue resolve_issue confirm_provisioning reopen decide_order]

    around_action :lock_operational_change, only: %i[update advance document_status add_issue resolve_issue confirm_provisioning reopen]

    def index
      scope = visible_to_current_user(crm_scope.jrc_crm_backoffice_requests)
              .includes(:sales_order, :contract, :contact, :owner, :requested_by, :business_unit, documents_attachments: :blob)
              .order(created_at: :desc)
      scope = scope.where(request_kind: params[:kind]) if params[:kind].present?
      scope = scope.where(stage: params[:stage]) if params[:stage].present?
      scope = scope.where(status: params[:status]) if params[:status].present?
      render json: scope.map { |request| serialize(request) }
    end

    def show
      render json: serialize(@request, include_history: true)
    end

    def summary
      scope = visible_to_current_user(crm_scope.jrc_crm_backoffice_requests)
      active = scope.where(status: JrcCrm::BackofficeRequest::ACTIVE_STATUSES)
      render json: {
        total: scope.count, pending: active.where(stage: %w[request analysis]).count,
        documentation: active.where(stage: 'documentation').count,
        implementation: active.where(stage: %w[implementation provisioning]).count,
        finance: active.where(stage: 'finance').count,
        issues: active.where(status: %w[blocked waiting_customer]).count,
        approvals: active.where(stage: 'approval').count,
        overdue: active.where(due_at: ...Time.current).count,
        completed: scope.where(status: 'completed').count
      }
    end

    def create
      attributes = request_params.to_h
      attributes['stage'] = 'analysis'
      attributes['status'] = 'pending'
      order = visible_to_current_user(crm_scope.jrc_crm_sales_orders).find(attributes.delete('sales_order_id'))
      contract_id = attributes.delete('contract_id')
      contract = contract_id.present? ? order.contracts.find(contract_id) : order.contracts.order(created_at: :desc).first
      owner_id = attributes.delete('owner_id')
      owner = owner_id.present? ? crm_scope.users.find(owner_id) : order.owner
      request = crm_scope.jrc_crm_backoffice_requests.create!(
        attributes.merge(sales_order: order, contract: contract, contact: order.contact, business_unit: order.business_unit,
                         owner: owner, requested_by: Current.user)
      )
      audit!(request, 'backoffice_created', {}, audit_snapshot(request))
      render json: serialize(request), status: :created
    end

    def update
      if @request.order_approval?
        return render json: { message: 'Use a decisão de aprovação do pedido.' }, status: :unprocessable_entity
      end
      before = audit_snapshot(@request)
      attributes = request_params.except(:sales_order_id, :contract_id, :owner_id).to_h
      owner_id = request_params[:owner_id]
      attributes[:owner] = crm_scope.users.find(owner_id) if owner_id.present?
      if (attributes['stage'].present? && attributes['stage'] != @request.stage) ||
         (attributes['status'].present? && attributes['status'] != @request.status &&
          !%w[pending in_progress waiting_customer blocked canceled approved rejected].include?(attributes['status']))
        return render json: { message: 'Use Avancar etapa ou Reabrir para alterar a etapa/concluir o fluxo.' }, status: :unprocessable_entity
      end
      attributes.delete('stage')
      incoming_metadata = (attributes.delete('metadata') || {}).except('document_statuses', 'provisioning_completed_at',
        'provisioning_completion_mode', 'provisioning_external_reference', 'provisioning_confirmed_by_id', 'approval_decision',
        'document_checklist', 'contract_required', 'source', 'implementation_project_id')
      attributes[:metadata] = (@request.metadata || {}).deep_merge(incoming_metadata)
      if %w[approved rejected].include?(attributes['status']) && attributes['status'] != @request.status
        unless crm_admin? && (@request.request_kind.in?(%w[approval change cancellation]) || @request.stage_applicable?('approval'))
          return render json: { message: 'Aprovacao requer administrador e solicitacao elegivel.' }, status: :forbidden
        end
        attributes[:metadata]['approval_decision'] = { 'status' => attributes['status'], 'actor_id' => Current.user.id,
                                                     'at' => Time.current.iso8601 }
      end
      @request.update!(attributes)
      audit!(@request, 'backoffice_updated', before, audit_snapshot(@request))
      render json: serialize(@request.reload)
    end

    def advance
      if @request.order_approval?
        return render json: { message: 'A aprovação do pedido exige decisão explícita.' }, status: :unprocessable_entity
      end
      before = audit_snapshot(@request)
      JrcCrm::BackofficeDocumentChecklist.new(request: @request, actor: Current.user).sync! if @request.fulfillment?
      @request.advance!
      audit!(@request, 'backoffice_stage_changed', before, audit_snapshot(@request))
      render json: serialize(@request.reload)
    rescue ActiveRecord::RecordInvalid => e
      render json: { message: e.message, errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    def upload_documents
      uploads = Array(params[:files]).compact
      return render json: { message: 'Selecione ao menos um documento.' }, status: :unprocessable_entity if uploads.empty?
      if uploads.length + @request.documents.count > 10 || uploads.any? { |file| !file.respond_to?(:size) || file.size > 20.megabytes }
        return render json: { message: 'Limite de 10 arquivos, ate 20 MB por arquivo.' }, status: :unprocessable_entity
      end
      uploads.each { |file| @request.documents.attach(file) }
      audit!(@request, 'backoffice_document_uploaded', {}, { filenames: uploads.map { |file| file.original_filename } })
      render json: { documents: documents_rows(@request.reload) }, status: :created
    end

    def download_document
      attachment = @request.documents.find(params[:attachment_id])
      send_data attachment.blob.download, filename: attachment.filename.to_s, type: attachment.content_type, disposition: 'attachment'
    end

    def document_status
      key = params[:document_key].to_s.presence || params[:attachment_id].to_s
      status = params[:status].to_s
      automatic = Array(@request.metadata['document_checklist']).any? { |row| row['key'] == key && row['source'] != 'manual' }
      return render json: { message: 'Este requisito é verificado no módulo de origem.' }, status: :unprocessable_entity if automatic
      return render json: { message: 'Status inválido.' }, status: :unprocessable_entity unless status.in?(%w[pending received validating approved rejected expired])

      attachment = params[:attachment_id].present? ? @request.documents.find(params[:attachment_id]) : nil
      if status == 'approved' && attachment.nil? && @request.required_documents.include?(key)
        return render json: { message: 'Anexe o documento obrigatório antes de aprová-lo.' }, status: :unprocessable_entity
      end

      metadata = (@request.metadata || {}).deep_dup
      metadata['document_statuses'] ||= {}
      previous = metadata['document_statuses'][key]
      metadata['document_statuses'][key] = status

      if attachment
        metadata['document_statuses'][attachment.id.to_s] = status
        filename = attachment.filename.to_s.parameterize
        @request.required_documents.each do |required_name|
          normalized = required_name.to_s.parameterize
          metadata['document_statuses'][required_name.to_s] = status if normalized.present? && filename.include?(normalized)
        end
      end

      @request.update!(metadata: metadata)
      JrcCrm::BackofficeDocumentChecklist.new(request: @request, actor: Current.user).sync! if @request.fulfillment?
      audit!(@request, 'backoffice_document_status_changed', { key: key, status: previous }, { key: key, status: status, attachment_id: attachment&.id })
      render json: serialize(@request.reload)
    end

    def add_issue
      description = params[:description].to_s.strip
      return render json: { message: 'Descreva a pendência.' }, status: :unprocessable_entity if description.blank?
      metadata = (@request.metadata || {}).deep_dup
      metadata['issues'] ||= []
      issue = { 'id' => SecureRandom.uuid, 'description' => description, 'type' => params[:issue_type].presence || 'operational',
                'status' => 'open', 'due_at' => params[:due_at], 'responsible_id' => params[:responsible_id],
                'created_at' => Time.current.iso8601, 'created_by_id' => Current.user&.id }
      metadata['issues'] << issue
      @request.update!(metadata: metadata, status: 'blocked')
      audit!(@request, 'backoffice_issue_created', {}, issue)
      render json: serialize(@request.reload)
    end

    def resolve_issue
      issue_id = params[:issue_id].to_s
      metadata = (@request.metadata || {}).deep_dup
      issue = Array(metadata['issues']).find { |row| row['id'].to_s == issue_id }
      return render json: { message: 'Pendência não encontrada.' }, status: :not_found unless issue
      issue['status'] = 'resolved'
      issue['resolved_at'] = Time.current.iso8601
      issue['resolved_by_id'] = Current.user&.id
      remaining = Array(metadata['issues']).reject { |row| %w[resolved canceled].include?(row['status'].to_s) }
      next_status = remaining.empty? && @request.status == 'blocked' ? 'in_progress' : @request.status
      @request.update!(metadata: metadata, status: next_status)
      audit!(@request, 'backoffice_issue_resolved', {}, issue)
      render json: serialize(@request.reload)
    end

    def confirm_provisioning
      mode = params[:mode].to_s
      unless mode.in?(%w[manual external])
        return render json: { message: 'Modo de provisionamento inválido.' }, status: :unprocessable_entity
      end

      external_reference = params[:external_reference].to_s.strip.presence
      if mode == 'external' && external_reference.blank?
        return render json: {
          message: 'Informe a referência retornada pela integração externa. O CRM não simula provisionamento concluído.'
        }, status: :unprocessable_entity
      end

      metadata = (@request.metadata || {}).deep_dup
      metadata['provisioning_completed_at'] = Time.current.iso8601
      metadata['provisioning_completion_mode'] = mode
      metadata['provisioning_external_reference'] = external_reference
      metadata['provisioning_confirmed_by_id'] = Current.user&.id
      @request.update!(metadata: metadata)
      audit!(@request, 'backoffice_provisioning_confirmed', {}, {
        mode: mode, external_reference: external_reference,
        completed_at: metadata['provisioning_completed_at']
      })
      render json: serialize(@request.reload)
    end

    def reopen
      ensure_crm_admin!
      return render json: { message: 'Crie uma nova solicitação de aprovação para este pedido.' }, status: :unprocessable_entity if @request.order_approval?
      target_stage = params[:stage].to_s.presence || 'analysis'
      unless JrcCrm::BackofficeRequest::STAGES.include?(target_stage) && target_stage != 'completed'
        return render json: { message: 'Etapa de reabertura inválida.' }, status: :unprocessable_entity
      end

      before = audit_snapshot(@request)
      if @request.fulfillment? && %w[implementation provisioning finance completed].include?(target_stage) &&
         (@request.stage_applicable?('contract') && @request.contract&.signature_status != 'signed')
        return render json: { message: 'A assinatura do contrato ainda está pendente.' }, status: :unprocessable_entity
      end
      @request.update!(stage: target_stage, status: 'in_progress', completed_at: nil)
      audit!(@request, 'backoffice_reopened', before, audit_snapshot(@request))
      render json: serialize(@request.reload)
    end

    def decide_order
      ensure_crm_admin!
      JrcCrm::OrderApprovalService.new(order: @request.sales_order, actor: Current.user)
        .decide!(request: @request, decision: params[:decision].to_s, reason: params[:reason])
      render json: serialize(@request.reload)
    rescue ArgumentError => error
      render json: { message: error.message }, status: :unprocessable_entity
    end

    private

    def lock_operational_change
      @request.sales_order.with_lock { @request.with_lock { yield } }
    end

    def set_request
      @request = visible_to_current_user(crm_scope.jrc_crm_backoffice_requests).find(params[:id])
    end

    def request_params
      params.require(:backoffice_request).permit(:sales_order_id, :contract_id, :owner_id, :request_kind, :stage, :status,
        :priority, :title, :description, :due_at, metadata: {})
    end

    def documents_rows(request)
      statuses = (request.metadata || {}).fetch('document_statuses', {})
      request.documents.map do |attachment|
        { id: attachment.id, filename: attachment.filename.to_s, content_type: attachment.content_type,
          byte_size: attachment.byte_size, status: statuses[attachment.id.to_s] || 'received', created_at: attachment.created_at }
      end
    end

    def serialize(request, include_history: false)
      order = request.sales_order
      data = {
        id: request.id, request_number: request.request_number, request_kind: request.request_kind,
        stage: request.stage, next_stage: request.next_applicable_stage, status: request.status, priority: request.priority,
        title: request.title, description: request.description, due_at: request.due_at, completed_at: request.completed_at,
        metadata: request.metadata, documents: documents_rows(request), created_at: request.created_at, updated_at: request.updated_at,
        order: { id: order.id, order_number: order.order_number, status: order.status, total_cents: order.total_cents,
                 monthly_cents: order.monthly_cents, items_count: order.order_items.size, snapshot: order.snapshot },
        contact: request.contact && { id: request.contact.id, name: request.contact.name, email: request.contact.email },
        contract: request.contract && { id: request.contract.id, contract_number: request.contract.contract_number,
                                        status: request.contract.status, signature_status: request.contract.signature_status },
        owner: { id: request.owner.id, name: request.owner.name },
        requested_by: { id: request.requested_by.id, name: request.requested_by.name },
        business_unit: request.business_unit && { id: request.business_unit.id, name: request.business_unit.name }
      }
      if include_history
        data[:history] = JrcCrm::AuditEvent.for_resource('JrcCrm::BackofficeRequest', request.id).recent.limit(200).map do |event|
          { id: event.id, event_type: event.event_type, from_value: event.from_value, to_value: event.to_value,
            metadata: event.metadata, actor_id: event.actor_id, created_at: event.created_at }
        end
      end
      data
    end

    def audit_snapshot(request)
      { stage: request.stage, status: request.status, priority: request.priority, owner_id: request.owner_id,
        due_at: request.due_at, completed_at: request.completed_at }
    end

    def audit!(request, event_type, from_value, to_value)
      JrcCrm::AuditEvent.create!(account_id: crm_scope.id, actor_type: 'User', actor_id: Current.user&.id,
        event_type: event_type, resource_type: 'JrcCrm::BackofficeRequest', resource_id: request.id,
        from_value: from_value, to_value: to_value, metadata: { source: 'crm_backoffice' })
    end
  end
end

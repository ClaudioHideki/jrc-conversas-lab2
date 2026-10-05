module Api::V1::Accounts::Crm
  class BackofficeRequestsController < BaseController
    QUALIFYING_ORDER_STATUSES = JrcCrm::OrderWorkflowSyncService::QUALIFYING_STATUSES.freeze

    before_action :set_request, only: %i[show update advance upload_documents download_document document_status add_issue
                                         resolve_issue return_issue reopen_issue upload_issue_evidence confirm_provisioning reopen]
    around_action :lock_operational_change, only: %i[update advance document_status add_issue resolve_issue return_issue
                                                      reopen_issue upload_issue_evidence confirm_provisioning reopen]

    def index
      scope = visible_to_current_user(crm_scope.jrc_crm_backoffice_requests)
              .includes(:sales_order, :contract, :contact, :owner, :requested_by, :business_unit,
                        :operations_queue, :operations_sla_policy, documents_attachments: :blob)
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
      sla_rows = active.includes(:operations_sla_policy).map { |request| JrcOperations::SlaClock.new(request).snapshot }
      completed_scope = scope.where(status: 'completed').where.not(completed_at: nil)
      completed_with_sla = completed_scope.where.not(sla_due_at: nil)
      compliant_completed = completed_with_sla.where('completed_at <= sla_due_at').count
      average_resolution_minutes = if completed_scope.exists?
                                     completed_scope.average("EXTRACT(EPOCH FROM (completed_at - created_at)) / 60.0").to_f.round(1)
                                   else
                                     0
                                   end
      compliance_percent = if completed_with_sla.exists?
                             ((compliant_completed.to_f / completed_with_sla.count) * 100).round(1)
                           else
                             nil
                           end
      render json: {
        total: scope.count, pending: active.where(stage: %w[request analysis]).count,
        documentation: active.where(stage: 'documentation').count,
        implementation: active.where(stage: %w[implementation provisioning]).count,
        finance: active.where(stage: 'finance').count,
        issues: active.where(status: %w[blocked waiting_customer]).count,
        approvals: active.where(stage: 'approval').count,
        overdue: sla_rows.count { |row| row[:state] == 'overdue' },
        watch: sla_rows.count { |row| row[:state] == 'watch' },
        attention: sla_rows.count { |row| row[:state] == 'attention' },
        critical: sla_rows.count { |row| row[:state] == 'critical' },
        within_sla: sla_rows.count { |row| row[:state] == 'within' },
        first_action_overdue: sla_rows.count { |row| row[:first_action_overdue] },
        stage_overdue: sla_rows.count { |row| row[:stage_overdue] },
        sla_compliance_percent: compliance_percent,
        average_resolution_minutes: average_resolution_minutes,
        completed: completed_scope.count
      }
    end

    # Explicit Backoffice eligibility endpoint. Never creates or updates data.
    def selection_options
      kind = params[:kind].presence_in(JrcCrm::BackofficeRequest.request_kinds.keys) || 'fulfillment'
      orders = visible_to_current_user(crm_scope.jrc_crm_sales_orders)
               .includes(:contact, :owner, :deal, :proposal, :contracts, :order_items, :backoffice_requests, :business_unit)
               .order(created_at: :desc)
      eligible = []
      waiting = []
      linked = []

      orders.each do |order|
        existing = order.backoffice_requests.detect do |request|
          request.request_kind == kind && (kind == 'fulfillment' || !request.status.in?(%w[completed canceled rejected]))
        end
        row = serialize_order_option(order, existing)
        if existing
          linked << row.merge(reason: "Já vinculada a #{existing.request_number}")
        elsif order.canceled?
          waiting << row.merge(reason: 'Pedido cancelado não é elegível.')
        elsif kind == 'fulfillment' && !QUALIFYING_ORDER_STATUSES.include?(order.status)
          waiting << row.merge(reason: "Aguardando aprovação do Pedido. Status atual: #{order.status}.")
        else
          eligible << row
        end
      end

      render json: { eligible: eligible, waiting: waiting, linked: linked,
                     rule: { kind: kind, qualifying_statuses: QUALIFYING_ORDER_STATUSES } }
    end

    def create
      attributes = request_params.to_h
      attributes['stage'] = 'analysis'
      attributes['status'] = 'pending'
      kind = attributes['request_kind'].presence || 'fulfillment'
      order = visible_to_current_user(crm_scope.jrc_crm_sales_orders)
              .includes(:backoffice_requests, :order_items, :contact, :owner, :business_unit)
              .find(attributes.delete('sales_order_id'))
      order.with_lock do
        validate_order_eligibility!(order, kind)

        contract_id = attributes.delete('contract_id')
        contract = contract_id.present? ? order.contracts.find(contract_id) : order.contracts.order(created_at: :desc).first
        owner_id = attributes.delete('owner_id')
        preferred_owner = owner_id.present? ? crm_scope.users.find(owner_id) : order.owner
        routing = JrcOperations::BackofficeRouter.new(account: crm_scope, order: order, request_kind: kind,
                                                       priority: attributes['priority'].presence || 'normal',
                                                       preferred_owner: preferred_owner).call
        request = crm_scope.jrc_crm_backoffice_requests.new(
          attributes.merge(sales_order: order, contract: contract, contact: order.contact, business_unit: order.business_unit,
                           owner: routing.owner || preferred_owner, requested_by: Current.user,
                           operations_queue: routing.queue, operations_sla_policy: routing.policy)
        )
        JrcOperations::SlaClock.new(request).start!
        request.due_at ||= request.sla_due_at
        request.save!
        audit!(request, 'backoffice_created', {}, audit_snapshot(request))
        render json: serialize(request), status: :created
      end
    end

    def update
      before = audit_snapshot(@request)
      previous_status = @request.status
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
        'provisioning_completion_mode', 'provisioning_external_reference', 'provisioning_confirmed_by_id', 'approval_decision', 'issues')
      attributes[:metadata] = (@request.metadata || {}).deep_merge(incoming_metadata)
      if %w[approved rejected].include?(attributes['status']) && attributes['status'] != @request.status
        unless crm_admin? && (@request.request_kind.in?(%w[approval change cancellation]) || @request.stage_applicable?('approval'))
          return render json: { message: 'Aprovacao requer administrador e solicitacao elegivel.' }, status: :forbidden
        end
        attributes[:metadata]['approval_decision'] = { 'status' => attributes['status'], 'actor_id' => Current.user.id,
                                                     'at' => Time.current.iso8601 }
      end
      @request.update!(attributes)
      clock = JrcOperations::SlaClock.new(@request)
      clock.mark_first_action!
      clock.status_changed!(from: previous_status, to: @request.status) if previous_status != @request.status
      audit!(@request, 'backoffice_updated', before, audit_snapshot(@request))
      render json: serialize(@request.reload)
    end

    def advance
      before = audit_snapshot(@request)
      JrcOperations::SlaClock.new(@request).mark_first_action!
      @request.advance!
      audit!(@request, 'backoffice_stage_changed', before, audit_snapshot(@request))
      render json: serialize(@request.reload)
    rescue ActiveRecord::RecordInvalid => e
      render json: { message: e.message, errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    def upload_documents
      uploads = Array(params[:files]).compact
      return render json: { message: 'Selecione ao menos um documento.' }, status: :unprocessable_entity if uploads.empty?
      if uploads.length + @request.documents.count > 20 || uploads.any? { |file| !file.respond_to?(:size) || file.size > 20.megabytes }
        return render json: { message: 'Limite de 20 arquivos, ate 20 MB por arquivo.' }, status: :unprocessable_entity
      end
      uploads.each { |file| @request.documents.attach(file) }
      JrcOperations::SlaClock.new(@request).mark_first_action!
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
      return render json: { message: 'Status inválido.' }, status: :unprocessable_entity unless status.in?(%w[pending received validating approved rejected expired])

      attachment = params[:attachment_id].present? ? @request.documents.find(params[:attachment_id]) : nil
      requirement = @request.document_requirements.find { |row| [row['key'], row['label']].include?(key) }
      if status == 'approved' && attachment.nil? && requirement&.fetch('required', false)
        return render json: { message: 'Anexe o documento obrigatório antes de aprová-lo.' }, status: :unprocessable_entity
      end

      metadata = (@request.metadata || {}).deep_dup
      metadata['document_statuses'] ||= {}
      previous = metadata['document_statuses'][key]
      metadata['document_statuses'][key] = status
      metadata['document_validations'] ||= []
      metadata['document_validations'] << {
        'key' => key, 'attachment_id' => attachment&.id, 'from' => previous, 'to' => status,
        'actor_id' => Current.user&.id, 'at' => Time.current.iso8601
      }

      if attachment
        metadata['document_statuses'][attachment.id.to_s] = status
        filename = attachment.filename.to_s.parameterize
        @request.document_requirements.each do |row|
          normalized = row['label'].to_s.parameterize
          if normalized.present? && filename.include?(normalized)
            metadata['document_statuses'][row['key']] = status
            metadata['document_statuses'][row['label']] = status
          end
        end
      end

      blocking_rejected = requirement&.fetch('blocking', false) && status.in?(%w[rejected expired])
      @request.update!(metadata: metadata, status: blocking_rejected ? 'blocked' : @request.status)
      JrcOperations::SlaClock.new(@request).mark_first_action!
      audit!(@request, 'backoffice_document_status_changed', { key: key, status: previous },
             { key: key, status: status, attachment_id: attachment&.id, requirement: requirement })
      auto_release_documentation!
      render json: serialize(@request.reload)
    end

    def add_issue
      description = params[:description].to_s.strip
      return render json: { message: 'Descreva a pendência.' }, status: :unprocessable_entity if description.blank?
      responsible_id = params[:responsible_id].presence
      responsible = responsible_id ? crm_scope.users.find(responsible_id) : @request.owner
      metadata = (@request.metadata || {}).deep_dup
      metadata['issues'] ||= []
      issue = {
        'id' => SecureRandom.uuid, 'description' => description, 'type' => params[:issue_type].presence || 'operational',
        'origin' => params[:origin].presence || @request.stage, 'responsible_area' => params[:responsible_area].presence,
        'responsible_id' => responsible&.id, 'priority' => params[:priority].presence || @request.priority,
        'status' => 'open', 'due_at' => params[:due_at], 'blocking' => boolean_param(params[:blocking], default: true),
        'created_at' => Time.current.iso8601, 'created_by_id' => Current.user&.id,
        'history' => [{ 'event' => 'opened', 'actor_id' => Current.user&.id, 'at' => Time.current.iso8601 }]
      }
      metadata['issues'] << issue
      next_status = issue['blocking'] ? 'blocked' : @request.status
      @request.update!(metadata: metadata, status: next_status)
      JrcOperations::SlaClock.new(@request).mark_first_action!
      audit!(@request, 'backoffice_issue_created', {}, issue)
      render json: serialize(@request.reload)
    end

    def resolve_issue
      issue, metadata = find_issue!
      resolution = params[:resolution].to_s.strip
      return render json: { message: 'Registre a solução aplicada antes de resolver a pendência.' }, status: :unprocessable_entity if resolution.blank?
      issue['status'] = 'resolved'
      issue['resolution'] = resolution
      issue['resolved_at'] = Time.current.iso8601
      issue['resolved_by_id'] = Current.user&.id
      append_issue_history(issue, 'resolved', resolution)
      remaining_blocking = Array(metadata['issues']).any? do |row|
        !%w[resolved canceled].include?(row['status'].to_s) && boolean_param(row['blocking'], default: true)
      end
      next_status = !remaining_blocking && @request.status == 'blocked' ? 'in_progress' : @request.status
      @request.update!(metadata: metadata, status: next_status)
      audit!(@request, 'backoffice_issue_resolved', {}, issue)
      render json: serialize(@request.reload)
    end

    def return_issue
      issue, metadata = find_issue!
      responsible_id = params[:responsible_id].presence || issue['responsible_id']
      return render json: { message: 'Informe o responsável para devolver a pendência.' }, status: :unprocessable_entity if responsible_id.blank?
      responsible = crm_scope.users.find(responsible_id)
      note = params[:note].to_s.strip
      issue['status'] = 'returned'
      issue['responsible_id'] = responsible.id
      issue['responsible_area'] = params[:responsible_area].presence || issue['responsible_area']
      issue['returned_at'] = Time.current.iso8601
      issue['returned_by_id'] = Current.user&.id
      append_issue_history(issue, 'returned', note, responsible_id: responsible.id)
      @request.update!(metadata: metadata, status: boolean_param(issue['blocking'], default: true) ? 'blocked' : @request.status)
      create_issue_task!(issue, responsible)
      @request.update!(metadata: metadata)
      audit!(@request, 'backoffice_issue_returned', {}, issue)
      render json: serialize(@request.reload)
    end

    def reopen_issue
      issue, metadata = find_issue!
      note = params[:note].to_s.strip
      issue['status'] = 'reopened'
      issue.delete('resolved_at')
      issue.delete('resolved_by_id')
      append_issue_history(issue, 'reopened', note)
      @request.update!(metadata: metadata, status: boolean_param(issue['blocking'], default: true) ? 'blocked' : @request.status)
      audit!(@request, 'backoffice_issue_reopened', {}, issue)
      render json: serialize(@request.reload)
    end

    def upload_issue_evidence
      issue, metadata = find_issue!
      uploads = Array(params[:files]).compact
      return render json: { message: 'Selecione ao menos uma evidência.' }, status: :unprocessable_entity if uploads.empty?
      if uploads.length + @request.documents.count > 20 || uploads.any? { |file| !file.respond_to?(:size) || file.size > 20.megabytes }
        return render json: { message: 'Limite de 20 arquivos, ate 20 MB por arquivo.' }, status: :unprocessable_entity
      end
      uploads.each { |file| @request.documents.attach(file) }
      @request.reload
      ids = @request.documents_attachments.order(created_at: :desc).limit(uploads.length).map(&:id)
      issue['evidence_attachment_ids'] = (Array(issue['evidence_attachment_ids']) + ids).uniq
      append_issue_history(issue, 'evidence_uploaded', uploads.map(&:original_filename).join(', '))
      @request.update!(metadata: metadata)
      audit!(@request, 'backoffice_issue_evidence_uploaded', {}, { issue_id: issue['id'], filenames: uploads.map(&:original_filename) })
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
      JrcOperations::SlaClock.new(@request).mark_first_action!
      audit!(@request, 'backoffice_provisioning_confirmed', {}, {
        mode: mode, external_reference: external_reference,
        completed_at: metadata['provisioning_completed_at']
      })
      render json: serialize(@request.reload)
    end

    def reopen
      target_stage = params[:stage].to_s.presence || 'analysis'
      unless JrcCrm::BackofficeRequest::STAGES.include?(target_stage) && target_stage != 'completed'
        return render json: { message: 'Etapa de reabertura inválida.' }, status: :unprocessable_entity
      end

      before = audit_snapshot(@request)
      @request.update!(stage: target_stage, status: 'in_progress', completed_at: nil)
      JrcOperations::SlaClock.new(@request).stage_changed!
      audit!(@request, 'backoffice_reopened', before, audit_snapshot(@request))
      render json: serialize(@request.reload)
    end

    private

    def lock_operational_change
      @request.with_lock { yield }
    end

    def set_request
      @request = visible_to_current_user(crm_scope.jrc_crm_backoffice_requests).find(params[:id])
    end

    def request_params
      params.require(:backoffice_request).permit(:sales_order_id, :contract_id, :owner_id, :request_kind, :stage, :status,
        :priority, :title, :description, :due_at, metadata: {})
    end

    def validate_order_eligibility!(order, kind)
      raise JrcCrm::CommercialFinancials::InvalidTerms, 'Pedido cancelado não é elegível para Backoffice.' if order.canceled?
      if kind == 'fulfillment' && !QUALIFYING_ORDER_STATUSES.include?(order.status)
        raise JrcCrm::CommercialFinancials::InvalidTerms,
              "Pedido precisa estar aprovado para Backoffice. Status atual: #{order.status}."
      end
      existing_scope = order.backoffice_requests.where(request_kind: kind)
      existing_scope = existing_scope.where.not(status: %w[completed canceled rejected]) unless kind == 'fulfillment'
      existing = existing_scope.first
      if existing
        raise JrcCrm::CommercialFinancials::InvalidTerms, "Pedido já está vinculado à solicitação #{existing.request_number}."
      end
    end

    def serialize_order_option(order, request = nil)
      {
        id: order.id, order_number: order.order_number, status: order.status, total_cents: order.total_cents,
        monthly_cents: order.monthly_cents, order_origin: order.order_origin,
        contact: order.contact && { id: order.contact.id, name: order.contact.name, company_id: order.contact.company_id },
        deal: order.deal && { id: order.deal.id, title: order.deal.title },
        proposal: order.proposal && { id: order.proposal.id, proposal_number: order.proposal.proposal_number },
        contract: order.contracts.order(created_at: :desc).first&.then { |contract| { id: contract.id, contract_number: contract.contract_number, status: contract.status } },
        owner: order.owner && { id: order.owner.id, name: order.owner.name },
        business_unit: order.business_unit && { id: order.business_unit.id, name: order.business_unit.name },
        items: order.order_items.map { |item| { id: item.id, product_id: item.product_id, name: item.name, quantity: item.quantity } },
        backoffice_request: request && { id: request.id, request_number: request.request_number, status: request.status, stage: request.stage }
      }
    end

    def documents_rows(request)
      statuses = (request.metadata || {}).fetch('document_statuses', {})
      request.documents.map do |attachment|
        { id: attachment.id, filename: attachment.filename.to_s, content_type: attachment.content_type,
          byte_size: attachment.byte_size, status: statuses[attachment.id.to_s] || 'received', created_at: attachment.created_at }
      end
    end

    def auto_release_documentation!
      return unless @request.stage == 'documentation'
      return if @request.blocking_open_issues.any?
      data = (@request.metadata || {}).with_indifferent_access
      statuses = (data[:document_statuses] || {}).with_indifferent_access
      pending = @request.blocking_document_requirements.reject do |row|
        statuses[row['key']].to_s == 'approved' || statuses[row['label']].to_s == 'approved'
      end
      return if pending.any?

      before = audit_snapshot(@request)
      @request.update!(status: 'in_progress') if @request.status == 'blocked'
      @request.advance!
      audit!(@request, 'backoffice_documentation_released', before, audit_snapshot(@request))
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.info("Backoffice documentation validated; next gate still pending: #{e.record.errors.full_messages.join(', ')}")
    end

    def find_issue!
      issue_id = params[:issue_id].to_s
      metadata = (@request.metadata || {}).deep_dup
      issue = Array(metadata['issues']).find { |row| row['id'].to_s == issue_id }
      raise ActiveRecord::RecordNotFound, 'Pendência não encontrada' unless issue

      [issue, metadata]
    end

    def append_issue_history(issue, event, note = nil, extra = {})
      issue['history'] ||= []
      issue['history'] << { 'event' => event, 'note' => note.presence, 'actor_id' => Current.user&.id,
                            'at' => Time.current.iso8601 }.merge(extra.stringify_keys)
    end

    def create_issue_task!(issue, responsible)
      order = @request.sales_order
      return unless order.deal

      activity = crm_scope.jrc_crm_activities.new(
        activity_type: 'task', title: "Pendência Backoffice #{@request.request_number}",
        description: issue['description'], due_at: issue['due_at'].presence && Time.zone.parse(issue['due_at'].to_s),
        user: responsible, deal: order.deal, contact: order.contact,
        metadata: { backoffice_request_id: @request.id, backoffice_issue_id: issue['id'], source: 'backoffice_return' }
      )
      result = JrcCrm::ActivityDispatchService.new(activity: activity, actor: Current.user).call
      issue['activity_id'] = result[:activity].id if result[:success]
      issue['activity_error'] = result[:error] unless result[:success]
    rescue ArgumentError => e
      issue['activity_error'] = e.message
    end

    def boolean_param(value, default: false)
      return default if value.nil?
      ActiveModel::Type::Boolean.new.cast(value)
    end

    def serialize(request, include_history: false)
      order = request.sales_order
      data = {
        id: request.id, request_number: request.request_number, request_kind: request.request_kind,
        stage: request.stage, next_stage: request.next_applicable_stage, status: request.status, priority: request.priority,
        title: request.title, description: request.description, due_at: request.due_at, completed_at: request.completed_at,
        metadata: request.metadata, document_requirements: request.document_requirements,
        documents: documents_rows(request), created_at: request.created_at, updated_at: request.updated_at,
        order: serialize_order_option(order),
        contact: request.contact && { id: request.contact.id, name: request.contact.name, email: request.contact.email,
                                      company_id: request.contact.company_id },
        contract: request.contract && { id: request.contract.id, contract_number: request.contract.contract_number,
                                        status: request.contract.status, signature_status: request.contract.signature_status },
        owner: { id: request.owner.id, name: request.owner.name },
        requested_by: { id: request.requested_by.id, name: request.requested_by.name },
        business_unit: request.business_unit && { id: request.business_unit.id, name: request.business_unit.name },
        queue: request.operations_queue && { id: request.operations_queue.id, name: request.operations_queue.name,
                                             code: request.operations_queue.code, assignment_strategy: request.operations_queue.assignment_strategy },
        sla_policy: request.operations_sla_policy && { id: request.operations_sla_policy.id,
                                                       name: request.operations_sla_policy.name },
        sla: JrcOperations::SlaClock.new(request).snapshot
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
        queue_id: request.operations_queue_id, sla_policy_id: request.operations_sla_policy_id,
        due_at: request.due_at, completed_at: request.completed_at }
    end

    def audit!(request, event_type, from_value, to_value)
      JrcCrm::AuditEvent.create!(account_id: crm_scope.id, actor_type: 'User', actor_id: Current.user&.id,
        event_type: event_type, resource_type: 'JrcCrm::BackofficeRequest', resource_id: request.id,
        from_value: from_value, to_value: to_value, metadata: { source: 'crm_backoffice' })
    end
  end
end

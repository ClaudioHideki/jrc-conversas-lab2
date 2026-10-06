module JrcCrm
  # Uses the existing Backoffice approval queue, keeping the order and decision atomic.
  class OrderApprovalService
    def initialize(order:, actor: nil)
      @order, @actor = order, actor || order.created_by || order.owner
    end

    def request!
      return unless @order.pending?
      @order.with_lock do
        request = @order.backoffice_requests.where(request_kind: 'approval')
          .where("metadata ->> 'source' = ?", 'order_approval').first_or_initialize
        next request if request.persisted?
        request.assign_attributes(account: @order.account, contact: @order.contact,
          business_unit: @order.business_unit, owner: @order.owner, requested_by: @actor,
          title: "Aprovar pedido #{@order.order_number}", stage: 'approval', status: 'pending',
          due_at: request.due_at || 2.days.from_now,
          metadata: (request.metadata || {}).merge('source' => 'order_approval',
            'order_total_cents' => @order.total_cents, 'monthly_cents' => @order.monthly_cents))
        request.save!
        request
      end
    end

    def decide!(request:, decision:, reason: nil)
      membership = @order.account.account_users.find_by(user_id: @actor&.id)
      raise Pundit::NotAuthorizedError unless membership&.administrator? && membership.permissions.include?('jrc_crm')
      raise ArgumentError, 'Decisão inválida.' unless %w[approved rejected returned].include?(decision)
      raise ArgumentError, 'Informe o motivo da recusa/devolução.' if decision != 'approved' && reason.to_s.strip.empty?
      @order.with_lock do
        request.lock!
        unless request.account_id == @order.account_id && request.sales_order_id == @order.id &&
               request.order_approval? && @order.pending? && request.status.in?(BackofficeRequest::ACTIVE_STATUSES)
          raise ArgumentError, 'Esta aprovação não está pendente para este pedido.'
        end
        metadata = (request.metadata || {}).merge('approval_decision' => {
          'status' => decision, 'reason' => reason.to_s.strip, 'actor_id' => @actor.id, 'at' => Time.current.iso8601
        })
        request.update!(status: decision == 'returned' ? 'waiting_customer' : decision, metadata: metadata)
        if decision == 'approved'
          @order.approval_authorized = true
          @order.update!(status: 'approved')
          OrderWorkflowSyncService.new(order: @order, actor: @actor).call
        end
        AuditEvent.create!(account: @order.account, actor_type: 'User', actor_id: @actor.id,
          resource_type: 'JrcCrm::BackofficeRequest', resource_id: request.id, event_type: 'backoffice_updated',
          from_value: { status: 'pending' }, to_value: { status: request.status }, metadata: metadata['approval_decision'])
        AuditEvent.create!(account: @order.account, actor_type: 'User', actor_id: @actor.id,
          resource_type: 'JrcCrm::SalesOrder', resource_id: @order.id, event_type: 'order_updated',
          from_value: { status: 'pending' }, to_value: { status: @order.status },
          metadata: { source: 'backoffice_approval', request_id: request.id, decision: decision })
      ensure
        @order.approval_authorized = false
      end
      request
    end
  end
end

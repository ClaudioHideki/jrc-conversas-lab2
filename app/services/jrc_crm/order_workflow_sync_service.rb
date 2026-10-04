module JrcCrm
  class OrderWorkflowSyncService
    QUALIFYING_STATUSES = %w[approved separating invoiced shipped completed].freeze

    def initialize(order:, actor:, event: 'order_approved')
      @order = order
      @actor = actor
      @event = event
    end

    def call
      @order.with_lock do
        if @order.canceled?
          reverse_downstream!
        else
          sync_follow_up! unless @order.draft?
          if QUALIFYING_STATUSES.include?(@order.status)
            contract = sync_contract!
            implementation = sync_implementation_project!
            sync_backoffice!(contract: contract, implementation: implementation)
            sync_commission!
          end
        end
      end
    end

    private

    def sync_follow_up!
      snapshot = (@order.snapshot || {}).with_indifferent_access
      return unless ActiveModel::Type::Boolean.new.cast(snapshot[:create_follow_up])

      @order.with_lock do
        activities = @order.account.jrc_crm_activities.where(activity_type: 'follow_up')
        next if activities.where("metadata @> ?", { sales_order_id: @order.id }.to_json).exists?

        due_at = Time.zone.parse(snapshot[:follow_up_due_at].to_s) if snapshot[:follow_up_due_at].present?
        unless @order.deal && due_at
          @order.errors.add(:base, 'Para criar o follow-up, informe negócio e data/hora de acompanhamento.')
          raise ActiveRecord::RecordInvalid, @order
        end
        activity = @order.account.jrc_crm_activities.new(
          activity_type: 'follow_up', title: "Follow-up do pedido #{@order.order_number}",
          due_at: due_at, user: @order.owner, deal: @order.deal, contact: @order.contact,
          metadata: { sales_order_id: @order.id }
        )
        result = JrcCrm::ActivityDispatchService.new(activity: activity, actor: @actor || @order.owner).call
        raise ActiveRecord::RecordInvalid, activity unless result[:success]
      end
    end

    def reverse_downstream!
      @order.commissions.find_each do |commission|
        commission.with_lock do
          commission.update!(status: 'reversed') unless CommissionProtection.final?(commission.status)
        end
      end
      @order.backoffice_requests.where.not(status: %w[completed canceled]).find_each do |request|
        request.update!(status: 'canceled')
      end
    end

    def sync_contract!
      JrcCrm::OrderContractService.new(order: @order, actor: @actor).call
    end

    def sync_implementation_project!
      JrcCrm::OrderImplementationProjectService.new(order: @order, actor: @actor).call
    end

    def sync_backoffice!(contract: nil, implementation: {})
      request = @order.backoffice_requests.find_or_initialize_by(request_kind: 'fulfillment')
      snap = (@order.snapshot || {}).with_indifferent_access
      existing_metadata = (request.metadata || {}).with_indifferent_access
      implementation_checklist = Array(existing_metadata[:implementation_checklist])
      if implementation_checklist.empty?
        implementation_checklist = Array(snap[:checklist]).map do |item|
          item.respond_to?(:to_h) ? item.to_h.deep_stringify_keys : { 'label' => item.to_s, 'done' => false }
        end
      end
      metadata = existing_metadata.to_h.merge(
        'order_total_cents' => @order.total_cents,
        'monthly_cents' => @order.monthly_cents,
        'implementation_required' => existing_metadata.fetch(:implementation_required) do
          ActiveModel::Type::Boolean.new.cast(snap[:send_to_implementation]) || implementation_checklist.any?
        end,
        'implementation_checklist' => implementation_checklist,
        'finance_required' => existing_metadata.fetch(:finance_required, true),
        'required_documents' => existing_metadata.fetch(:required_documents, Array(snap[:required_documents])),
        'provisioning_required' => existing_metadata.fetch(:provisioning_required, ActiveModel::Type::Boolean.new.cast(snap[:requires_provisioning])),
        'implementation_project_id' => implementation[:project]&.id || existing_metadata[:implementation_project_id],
        'implementation_project_warning' => implementation[:warning].presence || existing_metadata[:implementation_project_warning]
      )
      request.assign_attributes(
        account: @order.account, business_unit: @order.business_unit, contact: @order.contact,
        owner: @order.owner, requested_by: @actor || @order.owner,
        contract: contract || @order.contracts.order(created_at: :desc).first,
        title: "Processar pedido #{@order.order_number}", due_at: request.due_at || 2.days.from_now,
        metadata: metadata
      )
      if request.new_record?
        request.stage = stage_for_order(request)
        request.status = request.stage == 'completed' ? 'completed' : 'in_progress'
        request.completed_at = Time.current if request.stage == 'completed'
      end
      request.save!
      complete_after_payment!(request) if @event == 'payment_received'
    end

    def sync_commission!
      commission = @order.commissions.lock.find_or_initialize_by(user: @order.owner)
      return if commission.persisted? && CommissionProtection.final?(commission.status)

      program = eligible_program
      return unless program
      if program.rules_hash[:base].to_s == 'margin_cents' && margin_cents.nil?
        JrcCrm::AuditEvent.create!(account_id: @order.account_id, actor_type: 'User', actor_id: @actor&.id,
          event_type: 'commission_calculation_pending', resource_type: 'JrcCrm::SalesOrder', resource_id: @order.id,
          from_value: {}, to_value: {}, metadata: { reason: 'margin_unavailable', commission_program_id: program.id })
        return
      end

      attainment = goal_attainment_percent(program)
      sale = {
        total_cents: program.commission_base_cents(@order, base_key: 'total_cents'),
        monthly_cents: program.commission_base_cents(@order, base_key: 'monthly_cents'),
        received_cents: proportional_value(program, received_cents),
        margin_cents: proportional_value(program, margin_cents)
      }
      share = program.rules_hash[:share_percent].presence || 100
      result = JrcCrm::CommissionRulesEngine.new(
        rules: program.rules_hash,
        sale: sale,
        attainment_percent: attainment,
        share_percent: share
      ).call

      commission.assign_attributes(
        account: @order.account,
        business_unit: @order.business_unit,
        commission_program: program,
        base_cents: result[:base_cents],
        rate_percent: result[:rate_percent],
        commission_cents: result[:commission_cents],
        share_percent: result[:share_percent],
        goal_attainment_percent: result[:attainment_percent],
        calculation: result[:calculation].deep_stringify_keys,
        event_key: @event,
        accrued_at: Time.current,
        status: commission.new_record? ? initial_commission_status(program) : commission.status
      )
      commission.save!
    end

    def initial_commission_status(program)
      program.rules_hash[:requires_approval] == false ? 'released' : 'pending_approval'
    end

    def eligible_program
      date = (@order.sold_at || @order.closed_at || @order.created_at).to_date
      scope = @order.account.jrc_crm_commission_programs.active
                    .where(business_unit_id: [nil, @order.business_unit_id], release_condition: @event)
      scope.where('starts_on IS NULL OR starts_on <= ?', date)
           .where('ends_on IS NULL OR ends_on >= ?', date)
           .order(Arel.sql('business_unit_id NULLS LAST'), created_at: :desc)
           .detect { |program| program.eligible_for?(@order) }
    end

    def goal_attainment_percent(program)
      date = (@order.sold_at || @order.closed_at || @order.created_at).to_date
      goals = @order.account.jrc_crm_sales_goals.where(status: 'active')
                    .where('period_start <= ? AND period_end >= ?', date, date)
      linked_ids = Array(program.rules_hash[:goal_ids]).map(&:to_i).reject(&:zero?)
      goals = goals.where(id: linked_ids) if linked_ids.any?
      goal = goals.where('user_id = :uid OR allocations @> :allocation::jsonb',
                         uid: @order.owner_id, allocation: [{ user_id: @order.owner_id }].to_json)
                  .order(created_at: :desc).first
      goal ||= goals.where(scope_kind: 'company').order(created_at: :desc).first
      return nil unless goal

      JrcCrm::GoalProgressService.new(goal: goal, user_id: @order.owner_id).attainment_percent
    end

    def proportional_value(program, amount_cents)
      return nil if amount_cents.nil?
      return amount_cents.to_i unless program.product_restriction?
      total = @order.total_cents.to_i
      return 0 if total <= 0

      scoped = program.commission_base_cents(@order, base_key: 'total_cents')
      (amount_cents.to_i * scoped.to_d / total).round
    end

    def received_cents
      @order.invoices.joins(:payments).sum('jrc_crm_payments.amount_cents')
    rescue StandardError
      0
    end

    def margin_cents
      CommissionProtection.margin(@order.snapshot || {})
    end

    def stage_for_order(request)
      return 'completed' if @order.completed? && !request.stage_applicable?('implementation') && !request.stage_applicable?('provisioning')
      return 'finance' if @order.invoiced? || @order.shipped?
      return 'implementation' if @order.separating? && request.stage_applicable?('implementation')

      'analysis'
    end

    def complete_after_payment!(request)
      request.advance! until request.completed?
    rescue ActiveRecord::RecordInvalid => error
      # A payment is real even when a manual operational gate is still pending.
      # Never mark the backoffice completed merely because payment arrived.
      JrcCrm::AuditEvent.create!(account_id: @order.account_id, actor_type: 'User', actor_id: @actor&.id,
        event_type: 'backoffice_payment_gate_pending', resource_type: 'JrcCrm::BackofficeRequest', resource_id: request.id,
        from_value: {}, to_value: {}, metadata: { errors: error.record.errors.full_messages })
    end
  end
end

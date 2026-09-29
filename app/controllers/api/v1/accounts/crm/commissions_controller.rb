module Api::V1::Accounts::Crm
  class CommissionsController < BaseController
    ALLOWED_TRANSITIONS = {
      'forecast' => %w[pending_approval reversed],
      'pending_approval' => %w[released reversed],
      'released' => %w[paid reversed],
      'paid' => %w[reversed],
      'reversed' => []
    }.freeze

    def index
      render json: filtered_scope.map { |commission| serialize(commission) }
    end

    def summary
      scope = filtered_scope(relation: crm_scope.jrc_crm_sales_commissions)
      render json: {
        commissionable_base_cents: scope.where.not(status: 'reversed').sum(:base_cents),
        forecast_cents: scope.where(status: %w[forecast pending_approval]).sum(:commission_cents),
        pending_approval_cents: scope.where(status: 'pending_approval').sum(:commission_cents),
        released_cents: scope.where(status: 'released').sum(:commission_cents),
        paid_cents: scope.where(status: 'paid').sum(:commission_cents),
        reversed_cents: scope.where(status: 'reversed').sum(:commission_cents),
        count: scope.count,
        by_status: scope.group(:status).count
      }
    end

    def history
      scope = filtered_scope(relation: crm_scope.jrc_crm_sales_commissions)
      allowed_ids = scope.pluck(:id)
      events = JrcCrm::AuditEvent
               .where(account_id: crm_scope.id, resource_type: 'JrcCrm::SalesCommission', resource_id: allowed_ids)
               .recent.limit(500)
      render json: events.map { |event| serialize_event(event) }
    end

    def create
      ensure_crm_admin!
      attributes = commission_params.to_h
      order = crm_scope.jrc_crm_sales_orders.find(attributes.delete('sales_order_id'))
      user = crm_scope.users.find(attributes.delete('user_id'))
      commission = crm_scope.jrc_crm_sales_commissions.create!(attributes.merge(sales_order: order, user: user))
      audit_commission!(commission, 'commission_created', {}, serialize(commission))
      render json: serialize(commission), status: :created
    end

    def update
      ensure_crm_admin!
      commission = crm_scope.jrc_crm_sales_commissions.find(params[:id])
      commission.with_lock do
      before = serialize(commission)
      previous_status = commission.status
      attributes = commission_params.except(:sales_order_id, :user_id).to_h
      reason = attributes.delete('reversal_reason').to_s.strip
      if attributes['status'] == 'reversed' && commission.status != 'reversed' && reason.blank?
        commission.errors.add(:base, 'Informe o motivo do estorno.')
        raise ActiveRecord::RecordInvalid, commission
      end
      attributes['notes'] = [commission.notes.presence, "Estorno: #{reason}"].compact.join("\n") if reason.present?
      validate_transition!(commission, attributes['status']) if attributes['status'].present?
      attributes[:released_at] = Time.current if attributes['status'] == 'released' && commission.status != 'released'
      attributes[:paid_at] = Time.current if attributes['status'] == 'paid' && commission.status != 'paid'
      if manual_amount_change?(attributes, commission)
        result = JrcCrm::CommissionRulesEngine.new(
          rules: { base: 'total_cents', rate_percent: attributes.fetch('rate_percent', commission.rate_percent) },
          sale: { total_cents: attributes.fetch('base_cents', commission.base_cents) },
          share_percent: attributes.fetch('share_percent', commission.share_percent)
        ).call
        attributes[:commission_cents] = result[:commission_cents]
        attributes[:calculation] = result[:calculation].deep_stringify_keys.merge(
          'manual_adjustment' => true, 'adjusted_by_id' => Current.user&.id)
      end
      commission.update!(attributes)
      commission.reload
      event_type = previous_status != commission.status ? 'commission_status_changed' : 'commission_updated'
      audit_commission!(commission, event_type, before, serialize(commission))
      end
      render json: serialize(commission)
    end

    private

    def base_scope
      scope = crm_scope.jrc_crm_sales_commissions.includes(:user, :commission_program, sales_order: :order_items).order(created_at: :desc)
      scope = scope.where(user_id: Current.user.id) unless crm_admin?
      scope
    end

    def filtered_scope(relation: nil)
      scope = relation || base_scope
      scope = scope.where(user_id: Current.user.id) unless crm_admin? || relation.nil?
      scope = scope.where(user_id: Current.user.id) if params[:mine].to_s == 'true'
      scope = scope.where(status: params[:status]) if params[:status].present?
      scope = scope.where(user_id: params[:user_id]) if params[:user_id].present? && crm_admin?
      scope = scope.where(commission_program_id: params[:program_id]) if params[:program_id].present?
      if params[:start_date].present?
        scope = scope.where('jrc_crm_sales_commissions.created_at >= ?', parse_date(params[:start_date]).beginning_of_day)
      end
      if params[:end_date].present?
        scope = scope.where('jrc_crm_sales_commissions.created_at <= ?', parse_date(params[:end_date]).end_of_day)
      end
      scope
    end

    def commission_params
      params.require(:commission).permit(
        :sales_order_id, :user_id, :base_cents, :rate_percent, :status, :released_at, :paid_at, :notes,
        :share_percent, :goal_attainment_percent, :event_key, :reversal_reason, calculation: {}
      )
    end

    def validate_transition!(commission, target)
      return if target == commission.status
      allowed = ALLOWED_TRANSITIONS.fetch(commission.status, [])
      return if allowed.include?(target)

      commission.errors.add(:status, "transição #{commission.status} → #{target} não permitida")
      raise ActiveRecord::RecordInvalid, commission
    end

    def manual_amount_change?(attributes, commission)
      %w[base_cents rate_percent share_percent].any? do |key|
        attributes.key?(key) && attributes[key].to_d != commission.public_send(key).to_d
      end
    end

    def audit_commission!(commission, event_type, from_value, to_value)
      JrcCrm::AuditEvent.create!(
        account_id: crm_scope.id, actor_type: 'User', actor_id: Current.user&.id,
        event_type: event_type, resource_type: 'JrcCrm::SalesCommission', resource_id: commission.id,
        from_value: from_value, to_value: to_value, metadata: { source: 'crm_commissions' }
      )
    end

    def serialize_event(event)
      { id: event.id, commission_id: event.resource_id, event_type: event.event_type,
        from_value: event.from_value, to_value: event.to_value, metadata: event.metadata,
        actor_id: event.actor_id, created_at: event.created_at }
    end

    def serialize(commission)
      {
        id: commission.id, status: commission.status, base_cents: commission.base_cents,
        rate_percent: commission.rate_percent, share_percent: commission.share_percent,
        goal_attainment_percent: commission.goal_attainment_percent,
        commission_cents: commission.commission_cents, released_at: commission.released_at,
        paid_at: commission.paid_at, accrued_at: commission.accrued_at, event_key: commission.event_key,
        notes: commission.notes, calculation: commission.calculation,
        program: commission.commission_program && { id: commission.commission_program.id, name: commission.commission_program.name,
                                                     rules: commission.commission_program.rules },
        user: { id: commission.user.id, name: commission.user.name },
        order: {
          id: commission.sales_order.id, order_number: commission.sales_order.order_number,
          total_cents: commission.sales_order.total_cents, monthly_cents: commission.sales_order.monthly_cents,
          status: commission.sales_order.status,
          items: commission.sales_order.order_items.map { |item| { id: item.id, product_id: item.product_id,
            name: item.name, quantity: item.quantity, one_time_cents: item.one_time_cents,
            recurring_cents: item.recurring_cents } }
        },
        created_at: commission.created_at, updated_at: commission.updated_at
      }
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError
      Time.zone.today
    end
  end
end

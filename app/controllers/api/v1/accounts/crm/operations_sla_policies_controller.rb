module Api::V1::Accounts::Crm
  class OperationsSlaPoliciesController < BaseController
    before_action :require_crm_admin!, except: :index
    before_action :set_policy, only: :update

    def index
      scope = JrcOperations::SlaPolicy.where(account_id: crm_scope.id).includes(:operations_queue).order(active: :desc, name: :asc)
      render json: scope.map { |policy| serialize(policy) }
    end

    def create
      policy = JrcOperations::SlaPolicy.new(policy_params.merge(account: crm_scope))
      policy.transaction do
        policy.save!
        audit_configuration!(policy, {})
      end
      render json: serialize(policy), status: :created
    end

    def update
      @policy.with_lock do
        before = @policy.attributes
        @policy.update!(policy_params)
        audit_configuration!(@policy, before)
      end
      render json: serialize(@policy)
    end

    private

    def audit_configuration!(record, before)
      JrcCustomers::Audit.record!(account: crm_scope, actor: Current.user, resource: record, event_type: 'operations_configured',
        from_value: before, to_value: record.attributes)
    end

    def set_policy
      @policy = JrcOperations::SlaPolicy.where(account_id: crm_scope.id).find(params[:id])
    end

    def policy_params
      params.require(:operations_sla_policy).permit(:name, :operations_queue_id, :scope_kind, :request_kind, :priority,
                                                     :first_action_minutes, :stage_minutes, :total_minutes, :active,
                                                     conditions: {}, business_hours: {}, pause_statuses: [],
                                                     alert_thresholds: [], escalation: {})
    end

    def require_crm_admin!
      raise Pundit::NotAuthorizedError unless crm_admin?
    end

    def serialize(policy)
      {
        id: policy.id, name: policy.name, scope_kind: policy.scope_kind, request_kind: policy.request_kind,
        priority: policy.priority, first_action_minutes: policy.first_action_minutes,
        stage_minutes: policy.stage_minutes, total_minutes: policy.total_minutes, active: policy.active,
        conditions: policy.conditions, business_hours: policy.business_hours, pause_statuses: policy.pause_statuses,
        alert_thresholds: policy.alert_thresholds, escalation: policy.escalation,
        queue: policy.operations_queue && { id: policy.operations_queue.id, name: policy.operations_queue.name, code: policy.operations_queue.code },
        created_at: policy.created_at, updated_at: policy.updated_at
      }
    end
  end
end

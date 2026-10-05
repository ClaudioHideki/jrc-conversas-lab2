module Api::V1::Accounts::Crm
  class OperationsQueuesController < BaseController
    before_action :require_crm_admin!, except: :index
    before_action :set_queue, only: :update

    def index
      scope = JrcOperations::Queue.where(account_id: crm_scope.id).includes(:operating_company, :business_unit, :team).order(active: :desc, name: :asc)
      render json: scope.map { |queue| serialize(queue) }
    end

    def create
      queue = JrcOperations::Queue.new(queue_params.merge(account: crm_scope))
      queue.save!
      render json: serialize(queue), status: :created
    end

    def update
      @queue.update!(queue_params)
      render json: serialize(@queue)
    end

    private

    def set_queue
      @queue = JrcOperations::Queue.where(account_id: crm_scope.id).find(params[:id])
    end

    def queue_params
      params.require(:operations_queue).permit(:name, :code, :operating_company_id, :business_unit_id, :team_id, :assignment_strategy,
                                                :specialty, :active, settings: {})
    end

    def require_crm_admin!
      raise Pundit::NotAuthorizedError unless crm_admin?
    end

    def serialize(queue)
      {
        id: queue.id, name: queue.name, code: queue.code, assignment_strategy: queue.assignment_strategy,
        specialty: queue.specialty, active: queue.active, settings: queue.settings,
        operating_company: queue.operating_company && { id: queue.operating_company.id, name: queue.operating_company.name },
        business_unit: queue.business_unit && { id: queue.business_unit.id, name: queue.business_unit.name },
        team: queue.team && { id: queue.team.id, name: queue.team.name }, created_at: queue.created_at, updated_at: queue.updated_at
      }
    end
  end
end

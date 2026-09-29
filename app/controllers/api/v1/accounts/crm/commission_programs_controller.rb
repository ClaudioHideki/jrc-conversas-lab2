module Api::V1::Accounts::Crm
  class CommissionProgramsController < BaseController
    before_action :ensure_crm_admin!, only: %i[create update simulate]
    before_action :set_program, only: %i[show update]

    def index
      programs = crm_scope.jrc_crm_commission_programs.includes(:business_unit).order(active: :desc, created_at: :desc)
      render json: programs.map { |program| serialize(program) }
    end

    def show
      render json: serialize(@program)
    end

    def create
      program = crm_scope.jrc_crm_commission_programs.create!(normalized_program_params)
      render json: serialize(program), status: :created
    end

    def update
      @program.update!(normalized_program_params)
      render json: serialize(@program.reload)
    end

    def simulate
      rules = raw_rules
      sale = raw_sale
      if params[:sales_order_id].present?
        order = crm_scope.jrc_crm_sales_orders.includes(:order_items).find(params[:sales_order_id])
        sale = {
          total_cents: order.total_cents,
          monthly_cents: order.monthly_cents,
          received_cents: order.invoices.joins(:payments).sum('jrc_crm_payments.amount_cents'),
          margin_cents: (order.snapshot || {})['margin_cents'].presence || order.total_cents
        }
      end
      result = JrcCrm::CommissionRulesEngine.new(
        rules: rules, sale: sale,
        attainment_percent: params[:attainment_percent], share_percent: params[:share_percent].presence || rules.with_indifferent_access[:share_percent].presence || 100
      ).call
      render json: result
    end

    private

    def set_program
      @program = crm_scope.jrc_crm_commission_programs.find(params[:id])
    end

    def program_params
      params.require(:commission_program).permit(
        :name, :release_condition, :starts_on, :ends_on, :active, :business_unit_id,
        rules: {}
      )
    end

    def normalized_program_params
      attrs = program_params.to_h
      rules = (attrs['rules'] || {}).with_indifferent_access
      validate_rule_references!(rules)
      attrs['rules'] = rules.to_h
      attrs
    end

    def validate_rule_references!(rules)
      product_ids = Array(rules[:product_ids]).map(&:to_i).reject(&:zero?)
      user_ids = Array(rules[:user_ids]).map(&:to_i).reject(&:zero?)
      team_ids = Array(rules[:team_ids]).map(&:to_i).reject(&:zero?)
      goal_ids = Array(rules[:goal_ids]).map(&:to_i).reject(&:zero?)
      missing_products = product_ids - crm_scope.jrc_crm_products.where(id: product_ids).pluck(:id)
      missing_users = user_ids - crm_scope.users.where(id: user_ids).pluck(:id)
      missing_teams = team_ids - crm_scope.teams.where(id: team_ids).pluck(:id)
      missing_goals = goal_ids - crm_scope.jrc_crm_sales_goals.where(id: goal_ids).pluck(:id)
      raise ActiveRecord::RecordNotFound, "Produtos inválidos: #{missing_products.join(', ')}" if missing_products.any?
      raise ActiveRecord::RecordNotFound, "Usuários inválidos: #{missing_users.join(', ')}" if missing_users.any?
      raise ActiveRecord::RecordNotFound, "Equipes inválidas: #{missing_teams.join(', ')}" if missing_teams.any?
      raise ActiveRecord::RecordNotFound, "Metas inválidas: #{missing_goals.join(', ')}" if missing_goals.any?
    end

    def raw_rules
      params[:rules].respond_to?(:to_unsafe_h) ? params[:rules].to_unsafe_h : (params[:rules] || {})
    end

    def raw_sale
      params[:sale].respond_to?(:to_unsafe_h) ? params[:sale].to_unsafe_h : (params[:sale] || {})
    end

    def serialize(program)
      {
        id: program.id, name: program.name, release_condition: program.release_condition,
        starts_on: program.starts_on, ends_on: program.ends_on, active: program.active, rules: program.rules,
        business_unit: program.business_unit && { id: program.business_unit.id, name: program.business_unit.name },
        commissions_count: program.sales_commissions.count, created_at: program.created_at, updated_at: program.updated_at
      }
    end
  end
end

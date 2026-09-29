module Api::V1::Accounts::Crm
  class GoalsController < BaseController
    def index
      goals = crm_scope.jrc_crm_sales_goals.includes(:user, :team, :product).order(period_start: :desc, id: :desc)
      goals = visible_goals(goals)
      render json: goals.map { |goal| serialize(goal, include_progress: true) }
    end

    def create
      ensure_crm_admin!
      data = JrcCrm::SalesGoal.transaction do
        goal = crm_scope.jrc_crm_sales_goals.create!(normalized_params)
        serialize(goal, include_progress: true)
      end
      render json: data, status: :created
    end

    def update
      ensure_crm_admin!
      goal = crm_scope.jrc_crm_sales_goals.find(params[:id])
      attrs = normalized_params
      attrs[:published_at] = Time.current if attrs[:status] == 'active' && goal.status != 'active'
      data = goal.transaction do
        goal.update!(attrs)
        serialize(goal.reload, include_progress: true)
      end
      render json: data
    end

    def dashboard
      start_date = parse_date(params[:start_date]) || Time.zone.today.beginning_of_month
      end_date = parse_date(params[:end_date]) || start_date.end_of_month
      goals = crm_scope.jrc_crm_sales_goals.includes(:user, :team, :product)
                       .where(period_start: ..end_date, period_end: start_date..)
      active = visible_goals(goals.where(status: 'active'))
      active = visible_goals(goals) if active.none?

      progress_rows = active.map { |goal| [goal, JrcCrm::GoalProgressService.new(goal: goal, user_id: crm_admin? ? nil : Current.user.id).call] }
      target = progress_rows.sum { |goal, progress| monetary_goal?(goal) ? progress[:target].to_i : 0 }
      realized = progress_rows.sum { |goal, progress| monetary_goal?(goal) ? progress[:realized].to_i : 0 }

      deals = crm_scope.jrc_crm_deals.where(status: 'open')
      deals = deals.where(owner_id: Current.user.id) unless crm_admin?
      pipeline = deals.sum(:value_cents)
      weighted_pipeline = deals.sum { |deal| deal.weighted_value_cents.to_i }
      forecast = realized + weighted_pipeline

      render json: {
        period: { start: start_date, end: end_date }, target_cents: target, realized_cents: realized,
        pipeline_cents: pipeline, forecast_cents: forecast, gap_cents: [target - forecast, 0].max,
        attainment: percent(realized, target), goals_count: active.count,
        goals: progress_rows.map { |goal, progress| serialize(goal).merge(progress) },
        ranking: ranking(active), products: product_performance(active), evolution: evolution(start_date, end_date),
        by_type: active.group(:metric).count,
        status_summary: status_summary(active),
        history: history_rows(end_date),
        scope_options: crm_admin? ? {
          teams: crm_scope.teams.order(:name).select(:id, :name),
          business_units: JrcCrm::BusinessUnit.where(account_id: crm_scope.id, active: true).order(:name).select(:id, :name)
        } : {}
      }
    end

    private

    def visible_goals(scope)
      return scope if crm_admin?
      uid = Current.user.id
      scope.where('user_id = :uid OR allocations @> :allocation::jsonb', uid: uid, allocation: [{ user_id: uid }].to_json)
    end

    def goal_params
      params.require(:goal).permit(:name, :description, :user_id, :team_id, :business_unit_id, :product_id,
        :scope_kind, :metric, :period_start, :period_end, :period_kind, :target_cents, :target_quantity,
        :calculation_method, :currency, :status,
        allocations: [:user_id, :target_cents, :weight],
        product_targets: [:product_id, :target_cents],
        indicators: [:name, :kind, :metric, :target, :target_cents, :target_quantity, :weight], settings: {})
    end

    def normalized_params
      attrs = goal_params.to_h.deep_symbolize_keys
      if attrs.key?(:user_id)
        user_id = attrs.delete(:user_id)
        attrs[:user] = user_id.present? ? crm_scope.users.find(user_id) : nil
      end
      if attrs.key?(:team_id)
        team_id = attrs.delete(:team_id)
        attrs[:team] = team_id.present? ? crm_scope.teams.find(team_id) : nil
      end
      attrs[:allocations] = normalize_json_array(params.dig(:goal, :allocations)) if params.dig(:goal, :allocations)
      attrs[:product_targets] = normalize_json_array(params.dig(:goal, :product_targets)) if params.dig(:goal, :product_targets)
      attrs[:indicators] = normalize_json_array(params.dig(:goal, :indicators)) if params.dig(:goal, :indicators)
      attrs[:settings] = params.dig(:goal, :settings).to_unsafe_h if params.dig(:goal, :settings).respond_to?(:to_unsafe_h)
      attrs
    end

    def normalize_json_array(value)
      value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h.values : Array(value)
    end

    def serialize(goal, include_progress: false)
      data = {
        id: goal.id, name: goal.name, description: goal.description, status: goal.status, metric: goal.metric,
        scope_kind: goal.scope_kind, period_kind: goal.period_kind, period_start: goal.period_start, period_end: goal.period_end,
        target_cents: goal.target_cents, target_quantity: goal.target_quantity, calculation_method: goal.calculation_method,
        currency: goal.currency, team_id: goal.team_id, team_name: goal.team&.name, business_unit_id: goal.business_unit_id,
        product_id: goal.product_id, product_name: goal.product&.name, user: goal.user && { id: goal.user.id, name: goal.user.name },
        allocations: goal.allocations, product_targets: goal.product_targets, indicators: goal.indicators,
        settings: goal.settings, published_at: goal.published_at
      }
      data.merge!(JrcCrm::GoalProgressService.new(goal: goal, user_id: crm_admin? ? nil : Current.user.id).call) if include_progress
      data
    end

    def ranking(goals)
      allocations = goals.flat_map { |goal| Array(goal.allocations).map { |allocation| [goal, allocation] } }
      allocations.group_by { |_goal, allocation| (allocation['user_id'] || allocation[:user_id]).to_i }.filter_map do |uid, rows|
        next if !crm_admin? && uid != Current.user.id
        user = crm_scope.users.find_by(id: uid)
        next unless user
        target = rows.sum { |_g, allocation| (allocation['target_cents'] || allocation[:target_cents]).to_i }
        realized = rows.sum { |goal, _allocation| JrcCrm::GoalProgressService.new(goal: goal, user_id: uid).call[:realized].to_i }
        { user_id: uid, name: user.name, target_cents: target, realized_cents: realized, percent: percent(realized, target) }
      end.sort_by { |row| -row[:percent] }
    end

    def product_performance(goals)
      grouped = goals.flat_map { |goal| JrcCrm::GoalProgressService.new(goal: goal, user_id: crm_admin? ? nil : Current.user.id).product_results }.group_by { |row| row[:product_id] }
      grouped.map do |pid, rows|
        target = rows.sum { |row| row[:target_cents].to_i }
        realized = rows.sum { |row| row[:realized_cents].to_i }
        { product_id: pid, name: rows.first[:name], target_cents: target, realized_cents: realized, percent: percent(realized, target) }
      end
    end

    def evolution(start_date, end_date)
      orders = crm_scope.jrc_crm_sales_orders.where(status: %w[approved separating invoiced shipped completed])
                        .where('COALESCE(sold_at, closed_at, created_at) BETWEEN ? AND ?', start_date.beginning_of_day, end_date.end_of_day)
      orders = orders.where(owner_id: Current.user.id) unless crm_admin?
      totals = orders.to_a.group_by { |order| (order.sold_at || order.closed_at || order.created_at).to_date }
                     .transform_values { |rows| rows.sum(&:total_cents) }
      running = 0
      (start_date..end_date).map { |date| running += totals.fetch(date, 0); { date: date, realized_cents: running } }
    end

    def status_summary(goals)
      rows = goals.map { |goal| JrcCrm::GoalProgressService.new(goal: goal, user_id: crm_admin? ? nil : Current.user.id).attainment_percent }
      { achieved: rows.count { |p| p >= 100 }, on_track: rows.count { |p| p >= 75 && p < 100 },
        at_risk: rows.count { |p| p >= 50 && p < 75 }, not_achieved: rows.count { |p| p.positive? && p < 50 },
        not_started: rows.count(&:zero?) }
    end

    def history_rows(end_date)
      scope = visible_goals(crm_scope.jrc_crm_sales_goals.where('period_end < ?', end_date).order(period_end: :desc).limit(24))
      scope.map { |goal| serialize(goal, include_progress: true) }
    end

    def monetary_goal?(goal)
      %w[revenue mrr ticket].include?(goal.metric)
    end

    def percent(value, target)
      return 0 if target.to_f <= 0
      ((value.to_f / target.to_f) * 100).round(1)
    end

    def parse_date(value)
      Date.iso8601(value.to_s) if value.present?
    rescue ArgumentError
      nil
    end
  end
end

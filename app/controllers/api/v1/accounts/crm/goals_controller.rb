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
      reference_date = [[Time.zone.today, end_date].min, start_date].max
      ranking_rows = ranking(active, reference_date: reference_date)
      product_rows = product_performance(active)
      next_actions = actionable_next_actions(
        goals: active,
        deals: deals,
        ranking_rows: ranking_rows,
        product_rows: product_rows,
        target: target,
        realized: realized,
        pipeline: pipeline,
        forecast: forecast,
        reference_date: reference_date
      )

      render json: {
        period: { start: start_date, end: end_date, reference_date: reference_date },
        target_cents: target, realized_cents: realized,
        pipeline_cents: pipeline, forecast_cents: forecast, gap_cents: [target - forecast, 0].max,
        pipeline_coverage_percent: coverage_percent(pipeline, target), forecast_coverage_percent: coverage_percent(forecast, target),
        expected_progress_percent: aggregate_expected_progress(active, reference_date),
        attainment: percent(realized, target), goals_count: active.count,
        goals: progress_rows.map { |goal, progress| serialize(goal).merge(progress) },
        ranking: ranking_rows, products: product_rows, evolution: evolution(start_date, end_date),
        next_actions: next_actions,
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

    def ranking(goals, reference_date: Time.zone.today)
      allocations = goals.flat_map { |goal| Array(goal.allocations).map { |allocation| [goal, allocation] } }
      allocations.group_by { |_goal, allocation| (allocation['user_id'] || allocation[:user_id]).to_i }.filter_map do |uid, rows|
        next if !crm_admin? && uid != Current.user.id
        user = crm_scope.users.find_by(id: uid)
        next unless user

        target = rows.sum { |_g, allocation| (allocation['target_cents'] || allocation[:target_cents]).to_i }
        realized = rows.sum { |goal, _allocation| JrcCrm::GoalProgressService.new(goal: goal, user_id: uid).call[:realized].to_i }
        open_deals = crm_scope.jrc_crm_deals.where(status: 'open', owner_id: uid)
        pipeline = open_deals.sum(:value_cents)
        weighted_pipeline = open_deals.sum { |deal| deal.weighted_value_cents.to_i }
        forecast = realized + weighted_pipeline
        expected_target = rows.sum do |goal, allocation|
          row_target = (allocation['target_cents'] || allocation[:target_cents]).to_i
          (row_target * expected_progress_for(goal, reference_date) / 100.0).round
        end
        expected_percent = percent(expected_target, target)
        realized_percent = percent(realized, target)

        {
          user_id: uid, name: user.name, target_cents: target, realized_cents: realized,
          pipeline_cents: pipeline, forecast_cents: forecast, percent: realized_percent,
          forecast_percent: percent(forecast, target), expected_percent: expected_percent,
          below_pace: realized_percent < expected_percent,
          open_deals_count: open_deals.count
        }
      end.sort_by { |row| -row[:percent] }
    end

    def actionable_next_actions(goals:, deals:, ranking_rows:, product_rows:, target:, realized:, pipeline:, forecast:, reference_date:)
      gap = [target.to_i - forecast.to_i, 0].max
      pipeline_rows = pipeline_deal_rows(deals)
      stale_rows = pipeline_rows.select { |row| row[:stale] }.first(6)
      likely_rows = pipeline_rows.sort_by { |row| [-row[:probability].to_f, -row[:weighted_value_cents].to_i] }.first(6)
      seller_rows = ranking_rows.select { |row| row[:below_pace] }.sort_by { |row| row[:percent] }.first(6)
      proposal_rows = proposals_waiting_for_response(deals)
      expected_progress = aggregate_expected_progress(goals, reference_date)
      lagging_products = product_rows.select { |row| row[:percent].to_f < expected_progress.to_f }.sort_by { |row| row[:percent].to_f }.first(6)
      actions = []

      if gap.positive?
        actions << {
          key: 'goal_gap', title: "Gap de #{money_label(gap)}", priority: gap >= target.to_i * 0.5 ? 'critical' : 'high',
          value_cents: gap,
          reason: "O forecast ainda não cobre a meta. Faltam #{money_label(gap)} considerando realizado + pipeline ponderado.",
          deal_ids: likely_rows.map { |row| row[:id] }, records: likely_rows,
          nico_prompt: "Analise a meta comercial: faltam #{money_label(gap)}. Priorize oportunidades com maior chance de fechamento e indique as ações de hoje."
        }
      end

      if target.to_i.positive? && forecast.to_i < target.to_i
        coverage = coverage_percent(pipeline, target)
        actions << {
          key: 'pipeline_coverage', title: 'Aumentar cobertura de pipeline', priority: coverage < 100 ? 'critical' : 'high',
          value_percent: coverage,
          reason: "Pipeline atual de #{money_label(pipeline)} representa #{coverage}% da meta de #{money_label(target)}. Forecast cobre #{coverage_percent(forecast, target)}%.",
          deal_ids: pipeline_rows.first(12).map { |row| row[:id] }, records: pipeline_rows.first(6),
          nico_prompt: "A cobertura de pipeline é #{coverage}% e o forecast cobre #{coverage_percent(forecast, target)}% da meta. Analise os negócios abertos e proponha como elevar a cobertura."
        }
      end

      if seller_rows.any?
        actions << {
          key: 'sellers_below_pace', title: 'Vendedores abaixo do ritmo', priority: 'high',
          value_count: seller_rows.length,
          reason: "#{seller_rows.length} vendedor(es) estão abaixo do percentual esperado de #{expected_progress}% para a data atual.",
          records: seller_rows.map { |row| seller_record(row) },
          nico_prompt: "Analise os vendedores abaixo do ritmo da meta, comparando meta individual, realizado, forecast e percentual esperado. Sugira coaching e oportunidades prioritárias."
        }
      end

      if stale_rows.any?
        actions << {
          key: 'stale_deals', title: 'Oportunidades sem follow-up recente', priority: 'high',
          value_count: stale_rows.length,
          reason: "Existem #{stale_rows.length} oportunidades relevantes sem atividade comercial recente.",
          deal_ids: stale_rows.map { |row| row[:id] }, records: stale_rows,
          nico_prompt: "Analise as oportunidades paradas e recomende o melhor follow-up, canal e urgência para cada uma."
        }
      end

      if proposal_rows.any?
        actions << {
          key: 'proposals_waiting', title: 'Propostas sem retorno', priority: 'medium',
          value_count: proposal_rows.length,
          reason: "#{proposal_rows.length} proposta(s) enviada(s) ou visualizada(s) já atingiram o prazo de follow-up.",
          deal_ids: proposal_rows.map { |row| row[:deal_id] }.compact.uniq,
          records: proposal_rows,
          nico_prompt: "Analise as propostas sem retorno, identifique risco de perda e sugira a próxima abordagem para cada negociação."
        }
      end

      if lagging_products.any?
        actions << {
          key: 'products_below_goal', title: 'Produtos abaixo da meta', priority: 'medium',
          value_count: lagging_products.length,
          reason: "#{lagging_products.length} produto(s) estão abaixo do ritmo esperado de #{expected_progress}%.",
          records: lagging_products.map { |row| product_record(row) },
          nico_prompt: "Analise os produtos abaixo da meta e indique oportunidades, vendedores e ações comerciais para acelerar o resultado."
        }
      end

      if actions.empty?
        actions << {
          key: 'goal_on_track', title: 'Meta sob controle', priority: 'low', value_cents: realized,
          reason: 'Nenhum desvio crítico foi identificado para o período atual.', records: likely_rows.first(3),
          deal_ids: likely_rows.first(3).map { |row| row[:id] },
          nico_prompt: 'A meta está sob controle. Analise os dados atuais e indique as melhores ações preventivas para manter o ritmo.'
        }
      end

      actions.first(6)
    end

    def pipeline_deal_rows(deals)
      rows = deals.includes(:owner, :stage, :contact).order(value_cents: :desc).limit(100).to_a
      last_activities = JrcCrm::Activity.where(account_id: crm_scope.id, deal_id: rows.map(&:id)).group(:deal_id).maximum(:created_at)
      stale_before = 3.days.ago
      rows.map do |deal|
        last_activity = last_activities[deal.id]
        {
          type: 'deal', id: deal.id, label: deal.title,
          detail: [deal.contact&.name, deal.owner&.name, deal.stage&.name].compact.join(' · '),
          value_cents: deal.value_cents.to_i, weighted_value_cents: deal.weighted_value_cents.to_i,
          probability: deal.probability.to_f, owner_id: deal.owner_id,
          stage: deal.stage&.name, last_activity_at: last_activity,
          stale: last_activity.blank? || last_activity < stale_before
        }
      end
    end

    def proposals_waiting_for_response(deals)
      scope = crm_scope.jrc_crm_proposals.where(deal_id: deals.select(:id), status: %w[sent viewed])
                       .includes(:deal).order(updated_at: :asc).limit(100)
      now = Time.current
      scope.filter_map do |proposal|
        reference = proposal.last_viewed_at || proposal.viewed_at || proposal.sent_at || proposal.updated_at
        due_at = reference + proposal.follow_up_days.to_i.days
        next if due_at > now
        {
          type: 'proposal', id: proposal.id, deal_id: proposal.deal_id,
          label: proposal.proposal_number, detail: proposal.deal&.title,
          value_cents: proposal.total_cents.to_i, status: proposal.status,
          follow_up_due_at: due_at
        }
      end.first(6)
    end

    def seller_record(row)
      {
        type: 'seller', id: row[:user_id], owner_id: row[:user_id], label: row[:name],
        detail: "Meta #{money_label(row[:target_cents])} · Realizado #{money_label(row[:realized_cents])} · Forecast #{money_label(row[:forecast_cents])}",
        target_cents: row[:target_cents], realized_cents: row[:realized_cents], forecast_cents: row[:forecast_cents],
        percent: row[:percent], expected_percent: row[:expected_percent]
      }
    end

    def product_record(row)
      {
        type: 'product', id: row[:product_id], label: row[:name],
        detail: "#{row[:percent]}% atingido · #{money_label(row[:realized_cents])} de #{money_label(row[:target_cents])}",
        target_cents: row[:target_cents], realized_cents: row[:realized_cents], percent: row[:percent]
      }
    end

    def aggregate_expected_progress(goals, reference_date)
      monetary = goals.select { |goal| monetary_goal?(goal) && goal.target_cents.to_i.positive? }
      return 0 if monetary.empty?
      target = monetary.sum { |goal| goal.target_cents.to_i }
      expected = monetary.sum { |goal| goal.target_cents.to_i * expected_progress_for(goal, reference_date) / 100.0 }
      percent(expected, target)
    end

    def expected_progress_for(goal, reference_date)
      return 0 if reference_date < goal.period_start
      return 100 if reference_date >= goal.period_end
      total_days = (goal.period_end - goal.period_start).to_i + 1
      elapsed_days = (reference_date - goal.period_start).to_i + 1
      ((elapsed_days.to_f / total_days) * 100).round(1)
    end

    def money_label(cents)
      helpers.number_to_currency(cents.to_i / 100.0, unit: 'R$ ', separator: ',', delimiter: '.')
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

    def coverage_percent(value, target)
      return 0 if target.to_f <= 0
      ((value.to_f / target.to_f) * 100).round(2)
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

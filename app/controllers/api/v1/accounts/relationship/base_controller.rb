class Api::V1::Accounts::Relationship::BaseController < Api::V1::Accounts::BaseController
  before_action :relationship_context
  around_action :use_account_timezone
  rescue_from ActiveRecord::RecordInvalid do |error|
    render json: { errors: error.record.errors.full_messages }, status: :unprocessable_entity
  end
  rescue_from ArgumentError, KeyError do |error|
    render json: { errors: [error.message] }, status: :unprocessable_entity
  end
  rescue_from ActiveRecord::StaleObjectError, ActiveRecord::RecordNotUnique do |_error|
    render json: { errors: ['Record changed. Refresh before retrying.'] }, status: :conflict
  end

  private

  def use_account_timezone(&block)
    Time.use_zone(Time.find_zone(Current.account.reporting_timezone) || Time.zone, &block)
  end

  def render_unauthorized(message)
    render json: { error: message }, status: :forbidden
  end

  def relationship_context
    @relationship_context ||= JrcRelationship::Context.new(Current.account_user)
  end

  def presenter
    @presenter ||= JrcRelationship::Presenter.new(relationship_context)
  end

  def page(relation)
    number = params.fetch(:page, 1).to_i.clamp(1, 10_000)
    size = params.fetch(:per_page, 25).to_i.clamp(1, 50)
    [relation.limit(size).offset((number - 1) * size), { page: number, per_page: size, total: relation.unscope(:order).count }]
  end

  def filtered_assignments
    scope = relationship_context.assignments
    scope = scope.where(id: params[:assignment_id]) if params[:assignment_id].present?
    %w[owner_id team_id company_id business_unit_id status].each { |key| scope = scope.where(key => params[key]) if params[key].present? }
    scope = scope.where(owner_id: Current.user.id) if params[:mode] == 'mine'
    scope = scope.where(owner_id: nil) if params[:mode] == 'unassigned'
    if params[:agent_q].present?
      query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:agent_q].to_s.first(100))}%"
      scope = scope.where(owner_id: Current.account.users.where('users.name ILIKE ?', query).select(:id))
    end
    %w[segment_id complexity].each do |key|
      scope = scope.where('settings ->> ? = ?', key, params[key].to_s) if params[key].present?
    end
    snapshots = JrcRelationship::HealthSnapshot.where(account_id: Current.account.id, viewer_id: Current.user.id,
      access_signature: relationship_context.access_signature)
    snapshot_filter = %w[critical without_contact].include?(params[:mode]) || %w[score_min score_max mrr_min_cents mrr_max_cents band factor].any? { |key| params[key].present? }
    snapshots = JrcRelationship::SnapshotAccess.scope(relationship_context, snapshots) if snapshot_filter || params[:product_id].present?
    latest = snapshots.where(id: snapshots.select('MAX(id) AS id').group(:assignment_id))
    if params[:product_id].present?
      product = params[:product_id].to_i
      contracted = latest.where("signals -> 'products' @> ?::jsonb", [{ id: product }].to_json).select(:assignment_id)
      scope = scope.where("settings ->> 'product_id' = ?", product.to_s).or(scope.where(id: contracted))
    end
    if params[:mode] == 'without_contact'
      scope = scope.where(id: latest.where("(signals ->> 'days_without_contact')::integer >= ?", relationship_context.configuration.effective_rules['no_contact_days']).select(:assignment_id))
    end
    scope = scope.where(id: latest.where(band: %w[critical risk]).select(:assignment_id)) if params[:mode] == 'critical'
    %w[score_min score_max].each do |key|
      latest = latest.where("score #{key.ends_with?('min') ? '>=' : '<='} ?", Float(params[key]).clamp(0, 100)) if params[key].present?
    end
    %w[mrr_min_cents mrr_max_cents].each do |key|
      next unless params[key].present?
      latest = latest.where("(signals ->> 'mrr_cents')::bigint #{key.include?('min') ? '>=' : '<='} ?", params[key].to_i.clamp(0, 10**15))
    end
    latest = latest.where(band: params[:band]) if params[:band].present?
    if params[:factor].present?
      comparison = params[:factor_direction] == 'positive' ? '>= 80' : '< 60'
      latest = latest.where("EXISTS (SELECT 1 FROM jsonb_array_elements(factors) AS factor(value) WHERE factor.value ->> 'factor' = ? " \
        "AND factor.value ->> 'available' = 'true' AND (factor.value ->> 'normalized')::numeric #{comparison})", params[:factor])
    end
    scope = scope.where(id: latest.select(:assignment_id)) if snapshot_filter
    if params[:mode] == 'renewals'
      scope = scope.where(id: relationship_context.records(JrcRelationship::Renewal).where(status: %w[open negotiating],
        renewal_on: Date.current..(Date.current + params.fetch(:renewal_days, 90).to_i.clamp(1, 120))).select(:assignment_id))
    end
    if params[:mode] == 'expansion'
      visible_deals = JrcCustomers::Visibility.new(account: Current.account, user: Current.user, account_user: Current.account_user).crm(Current.account.jrc_crm_deals)
      scope = scope.where(id: JrcRelationship::ExpansionPipeline.open(relationship_context.records(JrcRelationship::ExpansionSignal), visible_deals).select(:assignment_id))
    end
    if params[:q].present?
      query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.first(100))}%"
      scope = scope.left_joins(:company, :contact).where('companies.name ILIKE ? OR contacts.name ILIKE ?', query, query)
    end
    scope
  end

  def report_period
    return unless params[:from].present?
    from = Date.iso8601(params[:from]); to = Date.iso8601(params.fetch(:to, params[:from]).presence || params[:from])
    raise ArgumentError, 'Invalid period' if to < from || (to - from).to_i > 366
    from.beginning_of_day..to.end_of_day
  end
end

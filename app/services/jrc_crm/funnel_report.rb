# Read-only data for the funnel. The controller supplies the same authorized
# deal relation used by the CRM list.
class JrcCrm::FunnelReport
  def initialize(account:, scope:, params:)
    @account = account
    @scope = scope
    @params = params
    @show_company_name = account.feature_enabled?('jrc_customer_master')
    @month = permitted_month
    @mode = params[:mode].presence || 'conversion'
    raise ActionController::BadRequest, 'Invalid funnel mode' unless %w[conversion portfolio].include?(@mode)
  end

  def call
    pipelines = @account.jrc_crm_pipelines.active.ordered
    pipeline = @params[:pipeline_id].present? ? pipelines.find(@params[:pipeline_id]) : pipelines.first
    result = {
      pipelines: pipelines.pluck(:id, :name).map { |id, name| { id: id, name: name } },
      stages: [], deals: [], teams: [], owners: [], pipeline_id: pipeline&.id, month: @month.strftime('%Y-%m'),
      as_of: Time.current.iso8601(6), timezone: Time.zone.tzinfo.name
    }
    return result unless pipeline

    scope = report_scope(pipeline)
    result[:teams] = options(scope, :team, 'teams')
    result[:owners] = options(scope, :owner, 'users')
    scope = scope.where(team_id: @params[:team_id]) if @params[:team_id].present?
    scope = scope.where(owner_id: @params[:owner_id]) if @params[:owner_id].present?

    stages = pipeline.stages.ordered.to_a
    visits = moves_by_deal(scope, stages.map(&:id).to_set)
    records = scope.includes(:owner, :contact, :company, :activities).order(created_at: :desc, id: :desc)
    result[:stages] = stages.map { |stage| stage.as_json(only: %i[id name active is_won is_lost is_terminal]) }
    result[:deals] = records.map { |deal| serialize(deal, visits.fetch(deal.id, [])) }
    result
  end

  private

  def permitted_month
    return Time.zone.today.beginning_of_month if @params[:month].blank?

    value = @params[:month].to_s
    raise ArgumentError unless value.match?(/\A\d{4}-\d{2}\z/)

    Date.iso8601("#{value}-01")
  rescue ArgumentError
    raise ActionController::BadRequest, 'Invalid funnel month'
  end

  def report_scope(pipeline)
    scope = @scope.where(pipeline_id: pipeline.id).where.not(status: 'archived')
    return scope.open_deals if @mode == 'portfolio'

    from = Time.zone.local(@month.year, @month.month)
    scope.where(created_at: from...from.next_month)
  end

  def options(scope, association, table)
    scope.joins(association).distinct.reorder(nil).pluck("#{table}.id", "#{table}.name")
         .sort_by(&:last).map { |id, name| { id: id, name: name } }
  end

  def moves_by_deal(scope, stage_ids)
    events = @account.jrc_crm_audit_events.where(
      resource_type: 'JrcCrm::Deal', event_type: 'deal_stage_changed',
      resource_id: scope.reorder(nil).reselect(:id)
    ).order(:created_at, :id).pluck(:resource_id, :from_value, :to_value, :created_at)
    events.each_with_object({}) do |(deal_id, raw_from, raw_to, at), moves|
      from = stage_id(raw_from, stage_ids)
      to = stage_id(raw_to, stage_ids)
      next if to.nil? || from == to

      (moves[deal_id] ||= []) << { from: from, to: to, at: at.iso8601(6) }
    end
  end

  def stage_id(value, stage_ids)
    value = value['stage_id'] if value.is_a?(Hash)
    id = Integer(value, exception: false)
    id if stage_ids.include?(id)
  end

  def serialize(deal, moves)
    {
      id: deal.id, title: deal.title,
      company_name: (@show_company_name && deal.company&.account_id == @account.id ? deal.company.name : nil),
      contact_name: (deal.contact&.account_id == @account.id ? deal.contact.name : nil),
      owner_id: deal.owner_id, owner_name: deal.owner.name, team_id: deal.team_id, value_cents: deal.value_cents, currency: deal.currency,
      stage_id: deal.stage_id, status: deal.status, created_at: deal.created_at.iso8601(6), updated_at: deal.updated_at.iso8601(6),
      won_at: deal.won_at&.iso8601(6), next_activity: deal.next_activity.present?, moves: moves
    }
  end
end

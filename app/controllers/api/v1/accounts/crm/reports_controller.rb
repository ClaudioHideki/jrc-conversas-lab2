class Api::V1::Accounts::Crm::ReportsController < Api::V1::Accounts::Crm::BaseController
  before_action :set_report_filters

  def index
    render json: {
      period: { start_date: @start_date, end_date: @end_date },
      summary: summary,
      leads_by_status: lead_status_counts,
      leads_by_source: group_count(leads_scope, :source),
      deals_by_status: group_count(deals_scope, :status),
      proposals_by_status: group_count(proposals_scope, :status),
      revenue_by_owner: revenue_by_owner,
      activities: activity_metrics
    }
  end

  private

  def set_report_filters
    @start_date = params[:start_date] ? Date.parse(params[:start_date]) : 30.days.ago.to_date
    @end_date = params[:end_date] ? Date.parse(params[:end_date]) : Date.current
    @owner_id = crm_admin? ? params[:owner_id] : Current.user.id
  end

  def summary
    crm_metrics(
      pipeline_id: params[:pipeline_id],
      owner_id: @owner_id,
      start_date: @start_date,
      end_date: @end_date
    ).call
  end

  def leads_scope
    scope = corporate_records(:jrc_crm_leads).where(created_at: report_period)
    @owner_id.present? ? scope.where(owner_id: @owner_id) : scope
  end

  def deals_scope
    scope = corporate_records(:jrc_crm_deals).where(created_at: report_period)
    scope = scope.where(pipeline_id: params[:pipeline_id]) if params[:pipeline_id].present?
    @owner_id.present? ? scope.where(owner_id: @owner_id) : scope
  end

  def proposals_scope
    scope = corporate_records(:jrc_crm_proposals).where(created_at: report_period)
    @owner_id.present? ? scope.joins(:deal).where(jrc_crm_deals: { owner_id: @owner_id }) : scope
  end

  def activity_metrics
    scope = corporate_records(:jrc_crm_activities).where(created_at: report_period)
    scope = scope.where(user_id: @owner_id) if @owner_id.present?
    { completed: scope.completed.count, pending: scope.pending.count, overdue: scope.overdue.count }
  end

  def revenue_by_owner
    totals = deals_scope.won_deals.group(:owner_id).sum(:value_cents)
    items = User.where(id: totals.keys).pluck(:id, :name).map do |id, name|
      { owner_id: id, owner_name: name, value_cents: totals[id] }
    end
    items.sort_by { |item| -item[:value_cents] }
  end

  def group_count(scope, field)
    items = scope.group(field).count.map do |name, count|
      { name: name.presence || 'unknown', count: count }
    end
    items.sort_by { |item| -item[:count] }
  end

  def lead_status_counts
    totals = leads_scope.group(:status).count.each_with_object(Hash.new(0)) do |(status, count), result|
      public_status = %w[unqualified lost].include?(status) ? 'discarded' : status
      result[public_status.presence || 'unknown'] += count
    end
    totals.map { |name, count| { name: name, count: count } }.sort_by { |item| -item[:count] }
  end

  def report_period
    @start_date.beginning_of_day..@end_date.end_of_day
  end
end

module JrcCrm
  class MetricsCalculatorService
    def initialize(account:, start_date:, end_date:, pipeline_id: nil, **context)
      @account = account
      @actor = context.fetch(:actor, nil)
      raise ArgumentError, 'Unknown metrics context' unless (context.keys - [:actor, :owner_id]).empty?

      @pipeline_id = pipeline_id
      @owner_id = context.fetch(:owner_id, nil)
      @start_date = start_date.beginning_of_day
      @end_date = end_date.end_of_day
    end

    def call
      {
        total_leads: count_leads,
        leads_count: count_leads,
        new_leads_count: count_new_leads,
        open_deals: count_open_deals,
        open_deals_count: count_open_deals,
        pipeline_value_cents: calculate_pipeline_value,
        won_revenue_cents: calculate_won_revenue,
        weighted_value_cents: calculate_weighted_value,
        conversion_rate: calculate_conversion_rate,
        avg_ticket_cents: calculate_avg_ticket,
        average_ticket_cents: calculate_avg_ticket,
        closed_won_count: count_won_deals,
        closed_lost_count: count_lost_deals,
        overdue_activities_count: overdue_activities_count,
        stalled_deals_count: stalled_deals_count,
        funnel_stages: funnel_stages
      }
    end

    private

    def base_deals
      deals = JrcCrm::CorporateCoverage.new(account: @account,
                                            user: @actor).restrict(@account.jrc_crm_deals).where(created_at: @start_date..@end_date)
      deals = deals.where(pipeline_id: @pipeline_id) if @pipeline_id.present?
      deals = deals.where(owner_id: @owner_id) if @owner_id.present?
      deals
    end

    def count_leads
      leads = JrcCrm::CorporateCoverage.new(account: @account,
                                            user: @actor).restrict(@account.jrc_crm_leads).where(created_at: @start_date..@end_date)
      leads = leads.where(owner_id: @owner_id) if @owner_id.present?
      leads.count
    end

    def count_new_leads
      leads = JrcCrm::CorporateCoverage.new(account: @account, user: @actor).restrict(@account.jrc_crm_leads).where(status: 'new')
      leads = leads.where(owner_id: @owner_id) if @owner_id.present?
      leads.count
    end

    def count_open_deals
      base_deals.where(status: 'open').count
    end

    def count_won_deals
      base_deals.where(status: 'won').count
    end

    def count_lost_deals
      base_deals.where(status: 'lost').count
    end

    def calculate_pipeline_value
      base_deals.where(status: 'open').sum(:value_cents)
    end

    def calculate_won_revenue
      base_deals.where(status: 'won').sum(:value_cents)
    end

    def calculate_weighted_value
      # Weighted value = value * probability
      # Simplified via SQL sum
      base_deals.where(status: 'open').joins(:stage).sum('jrc_crm_deals.value_cents * (jrc_crm_stages.probability / 100.0)').to_i
    end

    def calculate_conversion_rate
      total_closed = count_won_deals + count_lost_deals
      return 0 if total_closed.zero?
      
      ((count_won_deals.to_f / total_closed) * 100).round(2)
    end

    def calculate_avg_ticket
      won_count = count_won_deals
      return 0 if won_count.zero?

      (calculate_won_revenue / won_count).to_i
    end

    def overdue_activities_count
      activities = JrcCrm::CorporateCoverage.new(account: @account, user: @actor)
                                            .restrict(@account.jrc_crm_activities).where(completed_at: nil).where(
                                              'due_at < ?', Time.current
                                            )
      activities = activities.where(user_id: @owner_id) if @owner_id.present?
      activities.count
    end

    def stalled_deals_count
      base_deals.where(status: 'open').where('updated_at < ?', 7.days.ago).count
    end

    def funnel_stages
      pipeline = if @pipeline_id.present?
                   @account.jrc_crm_pipelines.find_by(id: @pipeline_id)
                 else
                   @account.jrc_crm_pipelines.active.ordered.first
                 end
      return [] unless pipeline

      counts = base_deals.where(pipeline_id: pipeline.id).group(:stage_id).count
      values = base_deals.where(pipeline_id: pipeline.id).group(:stage_id).sum(:value_cents)
      maximum = [counts.values.max.to_i, 1].max
      pipeline.stages.active.ordered.map do |stage|
        {
          id: stage.id,
          name: stage.name,
          deals_count: counts[stage.id].to_i,
          value_cents: values[stage.id].to_i,
          percentage: ((counts[stage.id].to_f / maximum) * 100).round
        }
      end
    end
  end
end

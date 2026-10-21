class JrcCampaigns::DashboardService
  METRIC_FIELDS = {
    sent: :sent_at,
    delivered: :delivered_at,
    read: :read_at,
    replied: :replied_at,
    failed: :failed_at
  }.freeze
  PERIODS = [7, 30, 90].freeze

  def initialize(account, period: 30, campaign_id: nil, delivery_channel: nil)
    @account = account
    @period_days = PERIODS.include?(period.to_i) ? period.to_i : nil
    @campaign_id = campaign_id.presence
    @delivery_channel = delivery_channel.presence_in(JrcCampaigns::Campaign::DELIVERY_CHANNELS)
  end

  def as_json
    {
      summary: summary_for(current_start, Time.current),
      previous_summary: previous_summary,
      series: time_series,
      failure_reasons: failure_reasons,
      generated_at: Time.current
    }
  end

  private

  attr_reader :account, :period_days, :campaign_id, :delivery_channel

  def campaigns
    @campaigns ||= begin
      relation = account.jrc_campaigns
      relation = relation.where(id: campaign_id) if campaign_id
      relation = relation.where(delivery_channel: delivery_channel) if delivery_channel
      relation
    end
  end

  def recipients
    @recipients ||= JrcCampaigns::Recipient.where(campaign_id: campaigns.select(:id))
  end

  def current_start
    @current_start ||= period_days ? (period_days - 1).days.ago.beginning_of_day : nil
  end

  def previous_summary
    return METRIC_FIELDS.keys.index_with { 0 } unless period_days

    previous_end = current_start
    previous_start = period_days.days.before(previous_end)
    summary_for(previous_start, previous_end)
  end

  def summary_for(from, to)
    METRIC_FIELDS.to_h do |metric, field|
      [metric, metric_scope(field, from, to).count]
    end
  end

  def metric_scope(field, from, to)
    relation = recipients.where.not(field => nil)
    relation = relation.where("jrc_campaign_recipients.#{field} >= ?", from) if from
    relation.where("jrc_campaign_recipients.#{field} < ?", to)
  end

  def time_series
    grouped = METRIC_FIELDS.to_h do |metric, field|
      values = metric_scope(field, current_start, Time.current)
               .group(Arel.sql("DATE(jrc_campaign_recipients.#{field})"))
               .count
      [metric, values.transform_keys(&:to_s)]
    end

    dates = if period_days
              (current_start.to_date..Time.zone.today).map(&:to_s)
            else
              grouped.values.flat_map(&:keys).uniq.sort
            end

    dates.map do |date|
      { date: date }.merge(METRIC_FIELDS.keys.index_with { |metric| grouped.dig(metric, date).to_i })
    end
  end

  def failure_reasons
    counts = metric_scope(:failed_at, current_start, Time.current).group(:error_message).count
    categorized = Hash.new(0)
    counts.each { |message, count| categorized[failure_category(message)] += count }

    %w[invalid_number opt_out provider temporary other].map do |key|
      { key: key, count: categorized[key] }
    end
  end

  def failure_category(message)
    value = message.to_s
    return 'invalid_number' if value.match?(/invalid|inv[aá]lid|phone|telefone|number|n[uú]mero|wa_id/i)
    return 'opt_out' if value.match?(/opt.?out|blacklist|bloque|recus|unsubscribe/i)
    return 'temporary' if value.match?(/tempor|timeout|rate.?limit|thrott|indispon|unavailable/i)
    return 'provider' if value.match?(/provider|meta|whatsapp|twilio|360dialog|api|token|template|smtp|oauth|e-?mail/i)

    'other'
  end
end

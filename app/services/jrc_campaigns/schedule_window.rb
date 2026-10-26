class JrcCampaigns::ScheduleWindow
  def initialize(campaign)
    @campaign = campaign
  end

  def next_time(base_time)
    time = base_time.in_time_zone(time_zone)
    14.times do
      return within_day(time) if allowed_day?(time) && before_end?(time)

      time = (time + 1.day).beginning_of_day
    end
    base_time
  end

  def time_zone
    # Unversioned legacy windows retain their original UTC meaning and approval.
    Time.find_zone!(config[:timezone].presence || 'UTC')
  end

  private

  attr_reader :campaign

  def config
    campaign.sending_window.with_indifferent_access
  end

  def allowed_day?(time)
    Array(config[:days]).map(&:to_i).include?(time.wday)
  end

  def within_day(time)
    start_time = time_zone.parse("#{time.to_date} #{config[:start].presence || '00:00'}")
    [time, start_time].max
  end

  def before_end?(time)
    end_time = time_zone.parse("#{time.to_date} #{config[:end].presence || '23:59'}")
    time <= end_time
  end
end

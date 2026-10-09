# frozen_string_literal: true

class JrcNico::Helpdesk::ReportWindow
  attr_reader :date, :from, :until_at

  def initialize(timezone, cutoff_at)
    @zone = TZInfo::Timezone.get(timezone)
    @until_at = cutoff_at
    @date = @zone.to_local(cutoff_at).to_date
    @from = first_local_instant
    raise ArgumentError, 'The local reporting interval cannot be reversed' unless @from <= @until_at
  end

  def to_h
    { 'from' => from.iso8601(6), 'until' => until_at.iso8601(6), 'basis' => 'local_day' }
  end

  private

  def first_local_instant
    local = Time.utc(date.year, date.month, date.day)
    # A DST transition may skip local midnight. Select the first actual minute of that date.
    181.times do |minute|
      instant = local_instant(local + (minute * 60))
      return instant if instant
    end
    raise ArgumentError, 'No valid local day boundary was found'
  end

  def local_instant(local)
    @zone.local_to_utc(local) { |periods| periods.max_by(&:utc_total_offset) }
  rescue TZInfo::PeriodNotFound
    nil
  end
end

# frozen_string_literal: true

class JrcServiceDesk::ManagerialReportDataset
  COLUMNS = %i[id title status phase priority requester company establishment unit assignee team queue service category subcategory ticket_type
               origin opened_at created_at updated_at closed_at closure_seconds first_response_result first_response_seconds
               resolution_result resolution_seconds].freeze
  DATE_COLUMNS = %i[opened_at created_at updated_at closed_at].freeze
  attr_reader :query, :observed_at, :labels, :locale

  def initialize(query)
    @query = query
    @observed_at = Time.current
    @locale = query.context.account.locale.to_s == 'pt_BR' ? :pt_BR : :en
    @labels = I18n.t('jrc_managerial_report', locale: locale, raise: true)
  end

  def count
    @count ||= query.relation.count
  end

  def timezone
    query.timezone.tzinfo.name
  end

  def metrics
    return unless query.context.managerial_reporting_allowed?(:indicators, unit: query.unit)

    @metrics ||= JrcServiceDesk::ManagerialReportMetrics.new(query, now: observed_at).call(count)
  end

  def each_row
    return enum_for(:each_row) unless block_given?

    measurements = JrcServiceDesk::ManagerialReportMeasurements.new(query, now: observed_at)
    query.each_row_batch { |batch| measurements.details(batch).each { |row| yield row } }
  end

  def columns
    labels.fetch(:columns).slice(*COLUMNS)
  end

  def detail(row, key)
    case key
    when :phase then labels[:phases][row[key].to_sym]
    when :origin then labels[:origins][row[key].to_sym]
    when :first_response_result then clock_value(row, 'first_response', :result)
    when :first_response_seconds then clock_value(row, 'first_response', :seconds)
    when :resolution_result then clock_value(row, 'resolution', :result)
    when :resolution_seconds then clock_value(row, 'resolution', :seconds)
    else row[key]
    end
  end

  def criteria
    source = query.filters.fetch('origin', 'all')
    rows = [[labels[:account], query.context.account.name], [labels[:columns][:unit], query.unit.name],
            [labels[:generated], observed_at.in_time_zone(query.timezone).iso8601], [labels[:timezone], timezone],
            [labels[:date_reference], labels[:columns][query.date_field.to_sym]],
            [labels[:from], query.filters.fetch('from', '—')], [labels[:to], query.filters.fetch('to', '—')],
            [labels[:columns][:origin], labels[:origins][source.to_sym]], [labels[:group], labels[:groups][query.group_by.to_sym]],
            [labels[:opening_cutoff], JrcServiceDesk::ManagerialReportQuery::FIRST_DATE.iso8601]]
    phase = query.filters['phase']
    rows << [labels[:columns][:phase], labels[:phases][phase.to_sym]] if phase
    query.selected_dimensions.each do |field, name|
      rows << [labels[:dimensions].fetch(field.to_sym), name || labels[:unassigned]]
    end
    rows
  end

  def summary_rows
    rows = [[labels[:total], count]]
    return rows unless metrics

    rows + metrics.fetch(:phases).map { |phase, value| [labels[:phases].fetch(phase.to_sym), value] } +
      %i[new_count in_service open_or_waiting closure_rate].map { |key| [labels[key], metrics[key]] } +
      [[labels[:closure_measured], metrics[:closure][:measured]], [labels[:closure_mean], metrics[:closure][:mean_seconds]]]
  end

  def sla_rows
    return [] unless metrics

    metrics[:sla].flat_map do |kind, data|
      data.map { |key, value| [labels[:clocks].fetch(kind.to_sym), labels[:sla].fetch(key), value] }
    end
  end

  def distribution_name(field, row)
    return labels[:origins].fetch(row[:id].to_sym) if field == 'origin'

    row[:name] || (field == 'assignee_membership_id' ? labels[:unassigned] : labels[:missing])
  end

  def clock_value(row, kind, key)
    value = row.fetch(:sla).dig(kind, key)
    key == :result ? labels[:results].fetch((value || 'unmeasured').to_sym) : value
  end
end

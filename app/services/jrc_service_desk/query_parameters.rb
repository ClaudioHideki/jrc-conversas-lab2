# frozen_string_literal: true

# Whitelist shared by list and KPI queries. Values are selectors, never grants.
class JrcServiceDesk::QueryParameters
  IDS = %w[unit_id operator_company_id status_id priority_id category_id queue_id assignee_id].freeze
  KEYS = (IDS + %w[q page per_page mine source sort]).freeze
  SORTS = %w[updated_at_desc created_at_desc created_at_asc].freeze
  attr_reader :values

  def initialize(input = {}, catalog: false)
    @values = JrcServiceDesk::Input.attributes(input, catalog ? %w[q page per_page unit_id operator_company_id sort] : KEYS)
    @values = @values.reject { |_key, v| v.nil? || v == '' }
    @values.each do |key, value|
      raise ArgumentError, 'Scalar filters required' unless value.is_a?(String) || value.is_a?(Integer)
      @values[key] = JrcServiceDesk::Input.id(value) if IDS.include?(key)
    end
    @values['page'] = integer(@values.fetch('page', 1), 1_000_000)
    @values['per_page'] = integer(@values.fetch('per_page', 20), 100)
    raise ArgumentError, 'Invalid sort' if @values['sort'] && !SORTS.include?(@values['sort'])
    raise ArgumentError, 'Invalid personal filter' if @values['mine'] && @values['mine'] != 'true'
    %w[q source].each do |key|
      next unless @values[key]
      raise ArgumentError, 'Invalid text filter' unless @values[key].is_a?(String) && @values[key].length <= (key == 'q' ? 200 : 40)
      @values[key] = @values[key].strip
    end
  end

  def [](key)
    values[key.to_s]
  end

  def page
    self['page']
  end

  def per_page
    self['per_page']
  end

  def offset
    (page - 1) * per_page
  end

  private

  def integer(value, maximum)
    result = JrcServiceDesk::Input.id(value)
    raise ArgumentError, 'Pagination outside supported range' if result > maximum
    result
  end
end

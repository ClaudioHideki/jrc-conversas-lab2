# frozen_string_literal: true

# Shape validation only. Neither this schema nor a stored project ID grants access.
class JrcContactCenter::EndingActions::TaskDefinition
  REQUIRED = %w[title priority estimated_minutes board_column_id].freeze
  IDS = %w[assignee_id parent_id board_column_id].freeze

  def call(input)
    invalid! unless input.is_a?(Hash)

    row = input.deep_stringify_keys
    invalid! unless row.keys.sort == %w[attributes due_after_days project_id] && row['attributes'].is_a?(Hash)
    attributes = task_attributes!(row.fetch('attributes'))
    offset = row.fetch('due_after_days')
    validate_offset!(offset, attributes)
    { 'project_id' => identifier!(row.fetch('project_id')), 'attributes' => attributes, 'due_after_days' => offset }
  end

  private

  def validate_offset!(offset, attributes)
    return if offset.nil?

    invalid! unless offset.is_a?(Integer) && offset.between?(0, 3650)
    invalid! if attributes.key?('due_on')
  end

  def task_attributes!(values)
    validate_attribute_header!(values)
    result = values.deep_dup
    IDS.each { |key| result[key] = identifier!(values[key]) if values.key?(key) && !values[key].nil? }
    invalid! unless result['board_column_id']

    validate_optional!(result)
    result
  end

  def validate_attribute_header!(values)
    allowed = JrcProjects::Tasks::Create::FIELDS + ['board_column_id']
    invalid! unless (values.keys - allowed).empty? && (REQUIRED - values.keys).empty?
    invalid! unless text?(values['title'], 240) && JrcProjects::Project::PRIORITIES.include?(values['priority'])
    minutes = values['estimated_minutes']
    invalid! unless minutes.is_a?(Integer) && minutes.between?(0, 2_147_483_647)
  end

  def validate_optional!(values)
    invalid! if values.key?('description') && !string?(values['description'], 6000)
    validate_labels!(values['labels']) if values.key?('labels')
    %w[starts_on due_on].each { |key| validate_date!(values[key]) if values.key?(key) }
    validate_date_order!(values)
  end

  def validate_date_order!(values)
    return unless values['starts_on'] && values['due_on']

    invalid! if Date.iso8601(values['due_on']) < Date.iso8601(values['starts_on'])
  end

  def validate_labels!(labels)
    valid = labels.is_a?(Array) && labels.length <= 20 && labels.all? { |label| text?(label, 80) }
    invalid! unless valid && labels.uniq == labels
  end

  def validate_date!(value)
    return if value.nil?

    invalid! unless string?(value, 10) && value.match?(/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/)

    invalid! unless Date.iso8601(value).year.between?(1, 9999)
  rescue Date::Error
    invalid!
  end

  def identifier!(value)
    valid = (value.is_a?(String) || value.is_a?(Integer)) && string?(value.to_s, 19) && value.to_s.match?(/\A[1-9][0-9]{0,18}\z/)
    invalid! unless valid && value.to_i <= 9_223_372_036_854_775_807

    value.to_s
  end

  def text?(value, maximum)
    string?(value, maximum) && value.strip.present? && value == value.strip
  end

  def string?(value, maximum)
    value.is_a?(String) && value.valid_encoding? && value.exclude?("\u0000") && value.length <= maximum
  end

  def invalid!
    raise JrcContactCenter::OperationError, 'invalid_ending_task_parameters'
  end
end

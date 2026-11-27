# frozen_string_literal: true

class JrcContactCenter::RecordingTaskInput
  attr_reader :project_id, :request_id, :attributes

  def initialize(values)
    validate_command!(values)
    @project_id = JrcServiceDesk::Input.id(values.fetch('project_id'))
    @request_id = values.fetch('request_id')
    valid_key = @request_id.is_a?(String) && @request_id.match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/)
    raise ArgumentError, 'Identificação da solicitação inválida.' unless valid_key

    @attributes = values.fetch('task')
    validate_attributes!
  end

  private

  def validate_command!(values)
    valid = values.is_a?(Hash) && values.keys.sort == %w[project_id request_id task] && values['task'].is_a?(Hash)
    raise ArgumentError, 'Solicitação de tarefa inválida.' unless valid
  end

  def validate_attributes!
    allowed = JrcProjects::Tasks::Create::FIELDS + ['board_column_id']
    raise ArgumentError, 'Campos de tarefa inválidos.' unless (@attributes.keys - allowed).empty? && valid_scalars? && valid_labels?
  end

  def valid_scalars?
    @attributes.except('labels').values.all? { |value| value.nil? || value.is_a?(String) || value.is_a?(Numeric) }
  end

  def valid_labels?
    return true unless @attributes.key?('labels')

    @attributes['labels'].is_a?(Array) && @attributes['labels'].all?(String)
  end
end

# frozen_string_literal: true

class JrcContactCenter::AcwFormInput
  ATTRIBUTES = %i[name description status definition request_id expected_revision].freeze
  attr_reader :name, :description, :status, :definition, :request_id, :expected_revision

  def initialize(**attributes)
    raise JrcContactCenter::OperationError, 'invalid_acw_form_revision' unless (attributes.keys - ATTRIBUTES).empty?

    name, description, status, definition, request_id, expected_revision = attributes.reverse_merge(description: '').values_at(*ATTRIBUTES)
    valid = valid_content?(name, description, status) && valid_precondition?(request_id, expected_revision)
    raise JrcContactCenter::OperationError, 'invalid_acw_form_revision' unless valid

    @definition = JrcContactCenter::AcwFormDefinition.new(definition).call
    @name = name.strip
    @description = description
    @status = status
    @request_id = request_id.downcase
    @expected_revision = expected_revision
  end

  def attributes
    { name: name, description: description, status: status, definition: definition, request_id: request_id }
  end

  def matches?(version)
    version.name == name && version.description == description && version.status == status &&
      version.definition == definition && version.revision == expected_revision + 1
  end

  private

  def valid_content?(name, description, status)
    valid_text?(name, 160, required: true) && valid_text?(description, 1000) && %w[active archived].include?(status)
  end

  def valid_text?(value, maximum, required: false)
    value.is_a?(String) && value.length <= maximum && value.exclude?("\0") && (!required || value.strip.present?)
  end

  def valid_precondition?(request_id, revision)
    revision.is_a?(Integer) && revision.between?(0, 2_147_483_646) && request_id.is_a?(String) &&
      request_id.match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i)
  end
end

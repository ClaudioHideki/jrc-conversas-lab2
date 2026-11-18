# frozen_string_literal: true

class JrcContactCenter::IvrDraftInput
  attr_reader :name, :status, :definition, :request_id, :expected_revision

  def initialize(name: nil, status: nil, definition: nil, request_id: nil, expected_revision: nil)
    valid = valid_content?(name, status) && valid_precondition?(request_id, expected_revision)
    raise JrcContactCenter::OperationError, 'invalid_ivr_revision' unless valid

    JrcContactCenter::IvrGraphSchema.validate!(definition)
    @name = name.strip
    @status = status
    @definition = definition.deep_dup
    @request_id = request_id.downcase
    @expected_revision = expected_revision
  end

  def matches?(version)
    version.name == name && version.status == status && version.definition == definition && version.revision == expected_revision + 1
  end

  def attributes
    { name: name, status: status, definition: definition, request_id: request_id }
  end

  private

  def valid_content?(name, status)
    name.is_a?(String) && name.strip.present? && name.length <= 160 && %w[draft archived].include?(status)
  end

  def valid_precondition?(request_id, revision)
    revision.is_a?(Integer) && revision >= 0 && request_id.is_a?(String) &&
      request_id.match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i)
  end
end

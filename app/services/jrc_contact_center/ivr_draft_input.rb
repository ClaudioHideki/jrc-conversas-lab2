# frozen_string_literal: true

class JrcContactCenter::IvrDraftInput
  attr_reader :name, :status, :definition, :request_id, :expected_revision

  def initialize(name:, status:, definition:, request_id:, expected_revision:)
    valid = name.is_a?(String) && name.strip.present? && name.length <= 160 && %w[draft archived].include?(status)
    valid &&= expected_revision.is_a?(Integer) && expected_revision >= 0
    valid &&= request_id.is_a?(String) && request_id.match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i)
    raise JrcContactCenter::OperationError, 'invalid_ivr_revision' unless valid

    JrcContactCenter::IvrGraphSchema.validate!(definition)
    @name, @status, @definition = name.strip, status, definition.deep_dup
    @request_id, @expected_revision = request_id.downcase, expected_revision
  end

  def matches?(version)
    version.name == name && version.status == status && version.definition == definition && version.revision == expected_revision + 1
  end

  def attributes
    { name: name, status: status, definition: definition, request_id: request_id }
  end
end

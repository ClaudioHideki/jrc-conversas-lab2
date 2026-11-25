# frozen_string_literal: true

# Only native editable fields. Caller identity, company, requester, unit and
# lifecycle transitions are deliberately absent; the native policies still run.
class JrcContactCenter::EndingActions::ServiceDeskUpdateDefinition
  FIELDS = %w[ticket_id expected_lock_version attributes].freeze
  ATTRIBUTES = %w[title description priority_id category_id ticket_type_id subcategory_id contract_id service_fields].freeze

  def call(value)
    input = JrcServiceDesk::Input.attributes(value, FIELDS)
    invalid! unless input.keys.sort == FIELDS.sort

    result = { 'ticket_id' => JrcServiceDesk::Input.id(input.fetch('ticket_id')).to_s,
               'expected_lock_version' => JrcServiceDesk::Input.version(input.fetch('expected_lock_version')),
               'attributes' => attributes!(input.fetch('attributes')) }
    invalid! unless JSON.generate(result).bytesize <= 262_144
    result
  rescue ArgumentError, JSON::GeneratorError, JSON::NestingError
    invalid!
  end

  private

  def attributes!(value)
    fields = JrcServiceDesk::Input.attributes(value, ATTRIBUTES).deep_dup
    invalid! if fields.empty?
    invalid! if fields.key?('title') && (!text?(fields['title']) || fields['title'].strip.empty?)
    invalid! unless fields['description'].nil? || text?(fields['description'])
    invalid! if fields.key?('service_fields') && !fields['service_fields'].is_a?(Hash)

    ATTRIBUTES.grep(/_id\z/).each do |key|
      fields[key] = JrcServiceDesk::Input.id(fields[key]).to_s unless fields[key].nil?
    end
    fields
  end

  def text?(value)
    value.is_a?(String) && value.valid_encoding? && value.exclude?("\u0000")
  end

  def invalid!
    raise JrcContactCenter::OperationError, 'invalid_ending_service_desk_update_definition'
  end
end

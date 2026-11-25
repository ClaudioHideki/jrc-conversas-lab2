# frozen_string_literal: true

# Structure only, never a grant. Requester/company/actor and external origin
# flags are resolved from authorized native sources by the internal adapter.
class JrcContactCenter::EndingActions::ServiceDeskDestinationDefinition
  FIELDS = %w[unit_id service_id attributes].freeze
  ATTRIBUTES = %w[title description status_id priority_id category_id queue_id team_id assignee_account_user_id
                  ticket_type_id subcategory_id contract_id impact_code urgency_code service_fields].freeze
  IDENTIFIERS = ATTRIBUTES.select { |key| key.end_with?('_id') }.freeze

  def call(value)
    input = JrcServiceDesk::Input.attributes(value, FIELDS)
    invalid! unless input.keys.sort == FIELDS.sort

    attributes = native_attributes!(input.fetch('attributes'))
    result = { 'unit_id' => JrcServiceDesk::Input.id(input.fetch('unit_id')).to_s,
               'service_id' => input['service_id'].nil? ? nil : JrcServiceDesk::Input.id(input.fetch('service_id')).to_s,
               'attributes' => attributes }
    invalid! unless JSON.generate(result).bytesize <= 262_144
    result
  rescue ArgumentError, JSON::GeneratorError, JSON::NestingError
    invalid!
  end

  private

  def native_attributes!(value)
    fields = JrcServiceDesk::Input.attributes(value, ATTRIBUTES).deep_dup
    validate_text_fields!(fields)
    invalid! if fields.key?('service_fields') && !fields['service_fields'].is_a?(Hash)

    IDENTIFIERS.each { |key| fields[key] = JrcServiceDesk::Input.id(fields[key]).to_s unless fields[key].nil? }
    fields
  end

  def validate_text_fields!(fields)
    invalid! unless text?(fields['title']) && fields['title'].strip.present?

    %w[description impact_code urgency_code].each { |key| invalid! unless fields[key].nil? || text?(fields[key]) }
  end

  def text?(value)
    value.is_a?(String) && value.valid_encoding? && value.exclude?("\u0000")
  end

  def invalid!
    raise JrcContactCenter::OperationError, 'invalid_ending_service_desk_definition'
  end
end

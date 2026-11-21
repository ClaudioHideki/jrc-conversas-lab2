# frozen_string_literal: true

# Selection only: neither a native TeamMember nor a permission/queue grant is created.
class JrcContactCenter::TeamSupervisionInput
  FIELDS = %w[primary_account_user_id additional_account_user_ids].freeze
  attr_reader :primary_id, :additional_ids

  def initialize(values)
    valid = values.is_a?(Hash) && values.keys.all?(String) && values.keys.sort == FIELDS.sort
    invalid! unless valid

    @primary_id = optional_identifier(values.fetch('primary_account_user_id'))
    @additional_ids = additional_identifiers(values.fetch('additional_account_user_ids'))
    freeze
  end

  def assignments
    rows = additional_ids.map { |id| { account_user_id: id, kind: 'additional' } }
    rows.unshift(account_user_id: primary_id, kind: 'primary') if primary_id
    rows
  end

  private

  def optional_identifier(value)
    value.nil? ? nil : identifier(value)
  end

  def additional_identifiers(values)
    invalid! unless values.is_a?(Array) && values.length <= 128

    ids = values.map { |value| identifier(value) }
    invalid! if ids.uniq.length != ids.length || ids.include?(@primary_id)

    ids.sort.freeze
  end

  def identifier(value)
    valid = value.is_a?(Integer) || (value.is_a?(String) && value.valid_encoding? && value.match?(/\A[1-9][0-9]{0,18}\z/))
    invalid! unless valid

    id = value.to_i
    invalid! unless id.positive? && id.bit_length <= 63

    id
  end

  def invalid!
    raise JrcContactCenter::OperationError, 'invalid_team_supervision'
  end
end

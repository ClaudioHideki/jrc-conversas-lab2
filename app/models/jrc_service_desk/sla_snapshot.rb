# frozen_string_literal: true

# Historical conditions, not a contract master, an external integration or a calculator.
class JrcServiceDesk::SlaSnapshot < JrcServiceDesk::TicketRecord
  include JrcServiceDesk::AppendOnly

  JSON_FIELDS = %w[contract_conditions policy_conditions calendar_conditions].freeze
  SOURCE_FIELDS = %w[source_system source_reference source_version policy_key policy_version calendar_key calendar_version].freeze
  FORBIDDEN_KEYS = /(?:password|secret|credential|access_token|refresh_token|api_key|authorization)/i

  has_many :sla_milestones, class_name: 'JrcServiceDesk::SlaMilestone', dependent: :restrict_with_error

  validates(*SOURCE_FIELDS, presence: true, length: { maximum: 255 })
  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: %i[account_id unit_id ticket_id] }
  validates :calendar_scope, inclusion: { in: %w[account operator_company unit] }
  validates :timezone, presence: true, length: { maximum: 100 }
  validates :captured_at, :applied_at, presence: true
  validates :payload_digest, format: { with: /\A[a-f0-9]{64}\z/ }
  validate :json_conditions_are_valid
  validate :timezone_is_explicit
  validate :digest_matches_payload

  def expected_digest
    value = attributes.slice(*(SOURCE_FIELDS + JSON_FIELDS + %w[calendar_scope timezone]))
    value['captured_at'] = captured_at&.utc&.iso8601(6)
    JrcServiceDesk::CanonicalJson.digest(value)
  end

  private

  def json_conditions_are_valid
    JSON_FIELDS.each do |field|
      value = public_send(field)
      unless value.is_a?(Hash)
        errors.add(field, 'must be a JSON object')
        next
      end
      JrcServiceDesk::CanonicalJson.dump(value)
      errors.add(field, 'must not contain credential fields') if forbidden_key?(value)
    rescue ArgumentError
      errors.add(field, 'must be a bounded JSON object')
    end
  end

  def forbidden_key?(value)
    case value
    when Hash
      value.any? { |key, item| key.to_s.match?(FORBIDDEN_KEYS) || forbidden_key?(item) }
    when Array
      value.any? { |item| forbidden_key?(item) }
    else
      false
    end
  end

  def timezone_is_explicit
    TZInfo::Timezone.get(timezone.to_s)
  rescue TZInfo::InvalidTimezoneIdentifier
    errors.add(:timezone, 'must be a valid IANA timezone')
  end

  def digest_matches_payload
    errors.add(:payload_digest, 'does not match the conditions') unless payload_digest == expected_digest
  rescue ArgumentError
    errors.add(:payload_digest, 'cannot be computed from invalid conditions')
  end
end

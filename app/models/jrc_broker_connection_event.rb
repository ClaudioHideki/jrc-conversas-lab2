class JrcBrokerConnectionEvent < ApplicationRecord
  TYPES = %w[CONNECT_REQUESTED RECONNECT_REQUESTED CONNECTED RECONNECTED DISCONNECT_REQUESTED DISCONNECTED
             QR_EXPIRED NUMBER_MISMATCH IDENTITY_CONFIRMED SESSION_FAILED DISTRIBUTION_FALLBACK CONFIGURATION_CHANGED PERMISSIONS_CHANGED].freeze
  SAFE_METADATA = %w[result reason fallback team_id effective_from conversation_id error_code source_ip operation_id
                     expected_number observed_number previous_name next_name requested_at previous_user_ids next_user_ids].freeze
  belongs_to :account
  belongs_to :inbox
  belongs_to :user, optional: true
  validates :event_type, inclusion: { in: TYPES }
  validates :occurred_at, presence: true
  validate :safe_context

  def readonly?
    super || persisted?
  end

  def delete
    raise ActiveRecord::ReadOnlyRecord, 'Connection history is append-only' if persisted?

    super
  end

  private

  def safe_context
    errors.add(:inbox, :invalid) unless inbox&.account_id == account_id
    return if metadata.is_a?(Hash) && (metadata.keys - SAFE_METADATA).empty? && metadata.values.all? { |value| safe_value?(value) }

    errors.add(:metadata, :invalid)
  end

  def safe_value?(value)
    case value
    when NilClass, Numeric, TrueClass, FalseClass then true
    when String then value.length <= 500
    when Array then value.size <= 100 && value.all? { |id| id.is_a?(Integer) && id.positive? }
    else false
    end
  end
end

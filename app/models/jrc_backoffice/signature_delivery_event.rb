class JrcBackoffice::SignatureDeliveryEvent < ApplicationRecord
  self.table_name = 'jrc_backoffice_signature_delivery_events'
  self.filter_attributes += [:source_snapshot]
  encrypts :source_snapshot, support_unencrypted_data: false
  STATES = { 'prepared' => 'prepared', 'dispatch_started' => 'dispatching', 'send_confirmed' => 'sent', 'send_uncertain' => 'uncertain',
             'send_rejected' => 'failed', 'sender_blocked' => 'blocked', 'canceled_before_send' => 'canceled',
             'completion_reported' => 'completion_reported', 'envelope_canceled' => 'canceled', 'envelope_declined' => 'declined' }.freeze
  TERMINAL = %w[send_rejected sender_blocked canceled_before_send envelope_canceled envelope_declined].freeze
  belongs_to :account
  belongs_to :delivery, class_name: 'JrcBackoffice::SignatureDelivery', inverse_of: :events
  belongs_to :connection, class_name: 'JrcBackoffice::SignatureConnection'
  validates :kind, inclusion: { in: STATES.keys }
  validates :event_key, presence: true, uniqueness: { scope: :delivery_id }
  validates :external_id, length: { maximum: 512 }, allow_nil: true
  validates :external_id, presence: true, if: -> { kind == 'send_confirmed' }
  validate :consistent_origin
  validate :external_binding
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Signature events are immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Signature events are immutable' }

  def snapshot
    JSON.parse(source_snapshot)
  end

  def serializable_hash(_options = nil)
    slice('id', 'delivery_id', 'kind', 'external_id', 'created_at')
  end

  private

  def consistent_origin
    valid = delivery && [account_id, connection_id] == [delivery.account_id, delivery.connection_id] &&
            snapshot.is_a?(Hash) && source_snapshot.bytesize <= 16.kilobytes
    errors.add(:delivery, 'must preserve its admitted account and connection') unless valid
  rescue JSON::ParserError
    errors.add(:source_snapshot, 'must be a bounded event')
  end

  def external_binding
    errors.add(:external_id, 'must be bound only by a confirmed send') if external_id && kind != 'send_confirmed'
  end
end

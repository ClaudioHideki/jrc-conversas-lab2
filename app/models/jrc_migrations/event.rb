class JrcMigrations::Event < ApplicationRecord
  self.table_name = 'jrc_migration_events'
  ACTIONS = %w[STAGED PREVIEWED EXECUTED RECONCILED ACCEPTED MEDIA_SCANNED MEDIA_RECOVERED].freeze
  belongs_to :account
  belongs_to :batch, class_name: 'JrcMigrations::Batch'
  belongs_to :user, optional: true
  validates :action, inclusion: { in: ACTIONS }
  validates :occurred_at, presence: true
  validate :safe_context

  def self.record!(batch:, user:, action:, metadata: {})
    create!(account_id: batch.account_id, batch: batch, user: user, action: action, metadata: metadata, occurred_at: Time.current)
  end

  def readonly?
    super || persisted?
  end

  def delete
    raise ActiveRecord::ReadOnlyRecord, 'Migration history is append-only' if persisted?

    super
  end

  private

  def safe_context
    errors.add(:batch, :invalid) unless batch&.account_id == account_id
    valid = metadata.is_a?(Hash) && (metadata.keys - %w[summary source_digest report note item_id media_id status scan_state]).empty? &&
      metadata.to_json.bytesize <= 10_000
    errors.add(:metadata, :invalid) unless valid
  end
end

class JrcBrokerIntegration < ApplicationRecord
  self.filter_attributes += [:encrypted_control_key]

  belongs_to :account
  validates :account_id, uniqueness: true
  validates :organization_id, :broker_origin, :encrypted_control_key, presence: true
  validates :organization_id, uniqueness: { scope: :broker_origin }
  validates :destination_revision, numericality: { only_integer: true, greater_than: 0 }
  after_save_commit :schedule_inbox_registration

  def serializable_hash(_options = nil)
    { 'configured' => persisted?, 'has_credential' => encrypted_control_key.present? }
  end

  private

  def schedule_inbox_registration
    JrcBroker::InboxSyncJob.enqueue_for(account)
  end
end

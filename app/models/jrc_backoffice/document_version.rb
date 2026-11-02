class JrcBackoffice::DocumentVersion < ApplicationRecord
  self.table_name = 'jrc_backoffice_document_versions'
  attr_accessor :new_upload_blob

  belongs_to :account
  belongs_to :backoffice_request, class_name: 'JrcCrm::BackofficeRequest'
  belongs_to :uploaded_by, class_name: 'User'
  has_one_attached :file
  has_one :analysis, class_name: 'JrcBackoffice::DocumentAnalysis', dependent: :restrict_with_exception
  has_many :decisions, class_name: 'JrcBackoffice::DocumentDecision', dependent: :restrict_with_exception

  validates :document_key, :idempotency_key, :sha256, presence: true
  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: %i[backoffice_request_id document_key] }
  validates :idempotency_key, uniqueness: { scope: :backoffice_request_id }
  validate :consistent_account
  after_create_commit { JrcBackoffice::DocumentPreanalysisJob.perform_later(id) }
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Document versions are immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Document versions are immutable' }
  after_rollback(on: :create) do
    JrcBackoffice::PrivateBlob.clean_uncommitted(new_upload_blob, marker: 'jrc_backoffice_document_upload')
  end

  def status
    decisions.order(id: :desc).first&.status || analysis&.state || 'processing'
  end

  private

  def consistent_account
    errors.add(:account, 'must match the request') if backoffice_request && backoffice_request.account_id != account_id
    errors.add(:uploaded_by, 'must belong to account') if uploaded_by && !account.users.exists?(uploaded_by.id)
  end
end

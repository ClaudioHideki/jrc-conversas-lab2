# frozen_string_literal: true

# Never resolve a published reference through an asset's mutable name/folder or its latest version.
class JrcContactCenter::AudioVersion < JrcContactCenter::ApplicationRecord
  include JrcApprovals::Immutable
  include JrcContactCenter::AdministrativeAuditable

  self.filter_attributes += %i[file_name idempotency_key input_digest blob_id]

  belongs_to :audio_asset, class_name: 'JrcContactCenter::AudioAsset', inverse_of: :versions
  belongs_to :blob, class_name: 'ActiveStorage::Blob'
  belongs_to :created_by, class_name: 'User'
  has_many :inspections, class_name: 'JrcContactCenter::AudioInspection', inverse_of: :audio_version, dependent: :restrict_with_error
  has_one :latest_inspection, lambda {
    select('DISTINCT ON (jrc_contact_center_audio_inspections.audio_version_id) jrc_contact_center_audio_inspections.*')
      .order(:audio_version_id, attempt: :desc)
  }, class_name: 'JrcContactCenter::AudioInspection', foreign_key: :audio_version_id,
     inverse_of: :audio_version, dependent: :restrict_with_error
  before_destroy(prepend: true) { raise ActiveRecord::ReadOnlyRecord, 'Institutional audio versions are immutable' if persisted? }

  validates :number, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :audio_asset_id }
  validates :byte_size, numericality: { only_integer: true, greater_than: 0 }
  validates :sha256, :input_digest, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :idempotency_key, format: { with: /\A[\w-]{16,100}\z/ }, uniqueness: { scope: %i[account_id unit_id created_by_id] }
  validates :file_name, presence: true, length: { maximum: 255 }, format: { without: /[\x00\r\n]/ }
  validates :content_type, inclusion: { in: %w[audio/mpeg audio/wav audio/ogg audio/mp4 audio/webm] }
  validates :source_kind, inclusion: { in: %w[user_upload browser_capture] }
  validate :native_origin
  validate :owned_blob
  validate :current_uploader, on: :create

  private

  def native_origin
    valid = audio_asset && audio_asset.account_id == account_id && audio_asset.unit_id == unit_id
    errors.add(:audio_asset, :invalid) unless valid
  end

  def current_uploader
    errors.add(:created_by, :invalid) unless AccountUser.exists?(account_id: account_id, user_id: created_by_id)
  end

  def owned_blob
    valid = blob && blob.metadata['jrc_contact_center_institutional_audio'] == true && blob.byte_size == byte_size
    errors.add(:blob, :invalid) unless valid
  end
end

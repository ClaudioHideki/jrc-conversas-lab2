# frozen_string_literal: true

# Technical observations grant neither access to a unit nor approval to publish on telephony.
class JrcContactCenter::AudioInspection < JrcContactCenter::ApplicationRecord
  include JrcApprovals::Immutable
  include JrcContactCenter::AdministrativeAuditable

  STATES = %w[clean infected unavailable checksum_mismatch].freeze

  belongs_to :audio_version, class_name: 'JrcContactCenter::AudioVersion', inverse_of: :inspections
  belongs_to :source_blob, class_name: 'ActiveStorage::Blob'
  belongs_to :created_by, class_name: 'User'

  validates :attempt, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :audio_version_id }
  validates :state, inclusion: { in: STATES }
  validates :probe_state, inclusion: { in: %w[not_run valid invalid unavailable] }
  validates :expected_sha256, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :observed_sha256, format: { with: /\A[0-9a-f]{64}\z/ }, allow_nil: true
  validates :scanner_adapter, inclusion: { in: ['clamav-instream-v1'] }
  validates :decoder_version, length: { maximum: 200 }, allow_nil: true
  validates :observed_at, presence: true
  validates :idempotency_key, format: { with: /\A[\w-]{16,100}\z/ }, uniqueness: { scope: %i[account_id unit_id created_by_id] }
  validates :input_digest, format: { with: /\A[0-9a-f]{64}\z/ }
  validate :native_origin
  validate :clean_observation
  validate :valid_metadata
  validate :scan_before_probe
  validate :creator_membership, on: :create
  self.filter_attributes += %i[source_blob_id idempotency_key input_digest]

  def ready?
    persisted? && state == 'clean' && probe_state == 'valid' && observed_sha256 == expected_sha256 && decoded_metadata?
  end

  private

  def native_origin
    valid = audio_version && audio_version.account_id == account_id && audio_version.unit_id == unit_id &&
            audio_version.blob_id == source_blob_id && audio_version.sha256 == expected_sha256
    errors.add(:audio_version, :invalid) unless valid
  end

  def clean_observation
    return unless state == 'clean'

    errors.add(:observed_sha256, :invalid) unless observed_sha256 == expected_sha256
  end

  def valid_metadata
    valid = probe_state == 'valid' ? decoded_metadata? : metadata == {} && decoder_version.nil?
    errors.add(:metadata, :invalid) unless valid
  end

  def decoded_metadata?
    JrcContactCenter::AudioMediaMetadata.valid?(metadata) && metadata['content_type'] == audio_version&.content_type &&
      decoder_version.is_a?(String) && decoder_version.start_with?('ffmpeg version ')
  end

  def creator_membership
    errors.add(:created_by, :invalid) unless created_by && AccountUser.exists?(account_id: account_id, user_id: created_by_id)
  end

  def scan_before_probe
    errors.add(:probe_state, :invalid) unless state == 'clean' || probe_state == 'not_run'
  end
end

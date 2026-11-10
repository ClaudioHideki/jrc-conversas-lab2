require 'openssl'

class JrcBackoffice::CompletionDossier < ApplicationRecord
  self.table_name = 'jrc_backoffice_completion_dossiers'
  self.filter_attributes += [:source_snapshot]
  encrypts :source_snapshot, support_unencrypted_data: false
  belongs_to :account
  belongs_to :backoffice_request, class_name: 'JrcCrm::BackofficeRequest'
  belongs_to :archive_blob, class_name: 'ActiveStorage::Blob'
  belongs_to :sealed_by, class_name: 'User'
  validates :number, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :backoffice_request_id }
  validates :manifest_digest, uniqueness: { scope: :backoffice_request_id }
  validates :source_digest, :manifest_digest, :archive_sha256, format: { with: /\A[a-f0-9]{64}\z/ }
  validate do
    errors.add(:source_snapshot, 'must preserve the exact dossier') unless source_snapshot.to_s.bytesize <= 2.megabytes && integrity?
  end
  before_validation(on: :update) { raise ActiveRecord::ReadOnlyRecord, 'Completion dossiers are immutable' }
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Completion dossiers are immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Completion dossiers are immutable' }

  def self.digest(data)
    key = Rails.application.key_generator.generate_key('jrc-completion-dossier-v1', 32)
    OpenSSL::HMAC.hexdigest('SHA256', key, JSON.generate(JrcServiceDesk::CanonicalJson.normalize(data)))
  end

  def snapshot
    JSON.parse(source_snapshot)
  end

  def self.manifest_digest(manifest, links, units)
    digest({ 'manifest' => manifest, 'source_links' => links, 'unit_refs' => units })
  end

  def integrity?
    data = snapshot
    refs = %w[account_id backoffice_request_id archive_blob_id sealed_by_id number manifest_digest archive_sha256]
    data['format_version'] == 1 && data.values_at(*refs) == attributes.values_at(*refs) &&
      self.class.digest(data) == source_digest &&
      self.class.manifest_digest(data.fetch('manifest'), data.fetch('source_links'), data.fetch('unit_refs')) == manifest_digest &&
      backoffice_request.account_id == account_id && archive_blob.byte_size == data.fetch('archive_bytes')
  rescue JSON::ParserError, TypeError, KeyError
    false
  end

  def presentation
    { id: id, number: number, sealed_at: created_at, sealed_by_id: sealed_by_id, manifest_digest: manifest_digest,
      source_digest: source_digest, archive_sha256: archive_sha256, archive_bytes: archive_blob.byte_size }
  end
end

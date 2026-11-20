# frozen_string_literal: true

require 'digest'

# Reads only an exact version with a current clean, decoded observation and current native authority.
class JrcContactCenter::AudioBytes
  Result = Struct.new(:bytes, :file_name, :content_type, :account_id, :unit_id, :version_id, :inspection_id, :sha256, keyword_init: true)

  def initialize(access:)
    @access = access
  end

  def call(asset_id:, version_id:)
    original, proof = @access.transaction { readable_version!(asset_id, version_id) }
    bytes = read_bytes(original)
    @access.transaction do
      current, latest = readable_version!(asset_id, version_id)
      valid = current.id == original.id && current.sha256 == original.sha256 && latest.id == proof.id
      raise JrcContactCenter::OperationError.new('institutional_audio_inspection_changed', status: :conflict) unless valid

      JrcContactCenter::ConfigurationAudit.write_audio_read!(current, inspection: latest, actor: @access.actor)
      result_for(bytes, current, latest)
    end
  rescue ActiveStorage::IntegrityError
    raise JrcContactCenter::OperationError, 'institutional_audio_integrity_failed'
  rescue ActiveStorage::FileNotFoundError, IOError, SystemCallError
    raise JrcContactCenter::OperationError.new('institutional_audio_bytes_unavailable', status: :service_unavailable)
  end

  private

  def result_for(bytes, version, proof)
    Result.new(bytes: bytes, file_name: version.file_name, content_type: version.content_type,
               account_id: @access.account.id.to_s, unit_id: version.unit_id.to_s,
               version_id: version.id.to_s, inspection_id: proof.id.to_s, sha256: version.sha256)
  end

  def readable_version!(asset_id, version_id)
    asset = @access.asset(asset_id)
    version = @access.versions(asset).find(@access.identifier!(version_id))
    proof = @access.inspections(version).order(attempt: :desc).first
    valid = proof&.ready? && proof.source_blob_id == version.blob_id && proof.expected_sha256 == version.sha256
    raise JrcContactCenter::OperationError.new('institutional_audio_not_verified', status: :conflict) unless valid

    [version, proof]
  end

  def read_bytes(version)
    limit = JrcContactCenter::AudioFileInput.max_bytes
    raise JrcContactCenter::OperationError, 'institutional_audio_read_limit_exceeded' unless version.byte_size.positive? && version.byte_size <= limit

    version.blob.open do |file|
      raise ActiveStorage::IntegrityError unless file.size == version.byte_size

      bytes = file.read(version.byte_size + 1)
      valid = bytes && bytes.bytesize == version.byte_size && Digest::SHA256.hexdigest(bytes) == version.sha256
      raise ActiveStorage::IntegrityError unless valid

      bytes
    end
  end
end

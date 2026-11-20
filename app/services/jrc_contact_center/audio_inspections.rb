# frozen_string_literal: true

require 'digest'
require 'json'

# A receipt belongs to exact immutable bytes and never grants publication or byte access.
class JrcContactCenter::AudioInspections
  def initialize(access:)
    @access = access
  end

  def create!(asset_id:, version_id:, key:)
    valid = key.is_a?(String) && key.match?(/\A[\w-]{16,100}\z/)
    raise JrcContactCenter::OperationError, 'invalid_institutional_audio_inspection_key' unless valid

    source = @access.transaction { current_version(asset_id, version_id) }
    digest = input_digest(source)
    existing = @access.transaction { replay!(current_version(asset_id, version_id), key, digest) }
    return existing if existing

    observed = JrcContactCenter::AudioSafetyObservation.new(access: @access).call(asset_id: source.audio_asset_id, version_id: source.id)
    persist!(asset_id, version_id, key, digest, observed)
  end

  private

  def current_version(asset_id, version_id)
    asset = @access.asset(asset_id)
    @access.versions(asset).find(@access.identifier!(version_id))
  end

  def input_digest(version)
    fields = ['institutional_audio_inspection_v1', @access.account.id.to_s, @access.actor.id.to_s,
              version.unit_id.to_s, version.id.to_s, version.sha256]
    Digest::SHA256.hexdigest(JSON.generate(fields))
  end

  def replay!(version, key, digest)
    record = JrcContactCenter::AudioInspection.find_by(account: @access.account, unit_id: version.unit_id,
                                                       created_by: @access.actor, idempotency_key: key)
    return unless record
    return record if record.input_digest == digest

    raise JrcContactCenter::OperationError.new('institutional_audio_inspection_key_conflict', status: :conflict)
  end

  def persist!(asset_id, version_id, key, digest, observed)
    JrcContactCenter::AudioInspection.transaction(requires_new: true) do
      @access.transaction do
        version = current_version(asset_id, version_id)
        existing = replay!(version, key, digest)
        next existing if existing

        valid = observed.version.id == version.id && observed.version.sha256 == version.sha256 && digest == input_digest(version)
        raise JrcContactCenter::OperationError, 'institutional_audio_integrity_failed' unless valid

        JrcContactCenter::AudioInspection.create!(inspection_attributes(version, key, digest, observed.attributes))
      end
    end
  end

  def inspection_attributes(version, key, digest, attributes)
    attributes.merge(account: @access.account, unit_id: version.unit_id, audio_version: version,
                     source_blob_id: version.blob_id, expected_sha256: version.sha256, created_by: @access.actor,
                     attempt: JrcContactCenter::AudioInspection.where(audio_version: version).maximum(:attempt).to_i + 1,
                     idempotency_key: key, input_digest: digest)
  end
end

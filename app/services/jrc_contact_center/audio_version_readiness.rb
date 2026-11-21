# frozen_string_literal: true

# Technical metadata only, never authority or proof that bytes can currently be returned.
# Callers must first resolve the exact version/observation through AudioLibraryAccess.
class JrcContactCenter::AudioVersionReadiness
  def self.check!(version:, proof:)
    valid = proof&.ready? && proof.source_blob_id == version.blob_id && proof.expected_sha256 == version.sha256
    raise JrcContactCenter::OperationError.new('institutional_audio_not_verified', status: :conflict) unless valid

    proof
  end
end

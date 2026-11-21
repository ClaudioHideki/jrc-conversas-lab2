# frozen_string_literal: true

class JrcContactCenter::AudioCopies < JrcContactCenter::AudioUploads
  def call(asset_id:, version_id:, attributes:, key:, expected:)
    @access.refresh!
    origin = JrcContactCenter::AudioCopyOrigin.new(access: @access, asset_id: asset_id, version_id: version_id, expected: expected)
    request = JrcContactCenter::AudioUploads::Request.new(
      unit_id: origin.unit_id, attributes: JrcContactCenter::AudioAssetAttributes.parse(attributes),
      key: key, source_kind: origin.source_kind, origin: origin
    )
    prepare_request!(request)
    digest = input_digest(request, origin.metadata)
    existing = replay_before_stage!(request, digest)
    return existing if existing

    origin.with_upload { |upload| receive!(request, upload) }
  end
end

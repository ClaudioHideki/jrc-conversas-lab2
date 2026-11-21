# frozen_string_literal: true

require 'json'
require 'digest'

# Validates owned staged bytes before final persistence. No telephony command or publication.
class JrcContactCenter::AudioUploads
  Request = Struct.new(:unit_id, :asset_id, :attributes, :key, :expected, :source_kind, :origin, keyword_init: true)

  def initialize(access:)
    @access = access
  end

  def create!(unit_id:, attributes:, file:, key:, source_kind: 'user_upload')
    request = Request.new(unit_id: unit_id, attributes: JrcContactCenter::AudioAssetAttributes.parse(attributes), key: key, source_kind: source_kind)
    receive!(request, file)
  end

  def replace!(asset_id:, file:, key:, expected:, source_kind: 'user_upload')
    request = Request.new(asset_id: asset_id, attributes: {}, key: key, expected: expected, source_kind: source_kind)
    receive!(request, file)
  end

  private

  def receive!(request, file)
    @pending_blob = nil
    prepare_request!(request)
    input = JrcContactCenter::AudioFileInput.new(file: file)
    digest = input_digest(request, input)
    replay = replay_before_stage!(request, digest)
    return replay if replay

    observation = inspect_staged!(request, input)
    version = @access.transaction { persist_or_replay!(request, input, digest, observation) }
    JrcContactCenter::PrivateAudioBlob.clean_uncommitted(@pending_blob) if version.blob_id != @pending_blob.id
    version
  rescue StandardError
    JrcContactCenter::PrivateAudioBlob.clean_uncommitted(@pending_blob)
    raise
  ensure
    @pending_blob = nil
  end

  def prepare_request!(request)
    validate_request!(request)
    @access.refresh!
    request.asset_id = @access.identifier!(request.asset_id) if request.asset_id
    request.unit_id = @access.asset(request.asset_id).unit_id if request.asset_id
    unit = @access.unit(request.unit_id)
    request.unit_id = unit.id.to_s
    request.origin&.authorize!(unit)
    return if request.asset_id

    prepare_creation!(request, unit)
  end

  def validate_request!(request)
    raise JrcContactCenter::OperationError, 'invalid_institutional_audio_source' unless %w[user_upload browser_capture].include?(request.source_kind)

    valid = request.key.is_a?(String) && request.key.match?(/\A[\w-]{16,100}\z/)
    raise JrcContactCenter::OperationError, 'invalid_institutional_audio_upload_key' unless valid
  end

  def prepare_creation!(request, unit)
    folder = @access.folder(request.attributes['folder_id'], unit: unit)
    request.attributes['folder_id'] = folder&.id&.to_s
    asset = JrcContactCenter::AudioAsset.new(request.attributes.merge('account' => @access.account, 'unit' => unit))
    raise ActiveRecord::RecordInvalid, asset unless asset.valid?
  end

  def current_origin!(request)
    unit = @access.unit(request.unit_id)
    request.origin&.authorize!(unit)
    return @access.asset(request.asset_id) if request.asset_id

    @access.folder(request.attributes['folder_id'], unit: unit)
    nil
  end

  def input_digest(request, input)
    fields = [@access.account.id.to_s, @access.actor.id.to_s, request.unit_id, request.asset_id,
              request.attributes.sort.to_h, input.filename, input.content_type, input.byte_size, input.sha256]
    # Keep canonical digests of historical uploads identical. Capture origin never grants permission.
    fields << request.source_kind if request.source_kind != 'user_upload'
    fields << request.origin.digest_binding if request.origin
    Digest::SHA256.hexdigest(JSON.generate(fields))
  end

  def replay!(request, digest)
    version = JrcContactCenter::AudioVersion.find_by(account: @access.account, unit_id: request.unit_id,
                                                     created_by: @access.actor, idempotency_key: request.key)
    return unless version
    return version if version.input_digest == digest

    raise JrcContactCenter::OperationError.new('institutional_audio_upload_key_conflict', status: :conflict)
  end

  def replay_before_stage!(request, digest)
    @access.transaction do
      asset = current_origin!(request)
      existing = replay!(request, digest)
      next existing if existing

      check_revision!(asset, request)
      nil
    end
  end

  def check_revision!(asset, request)
    request.origin&.check_revision!
    return unless asset

    JrcContactCenter::AudioAssetRevision.check!(asset, version: @access.latest(asset), expected: request.expected)
  end

  def stage!(input)
    @pending_blob = JrcContactCenter::PrivateAudioBlob.upload(file: input.file, filename: input.filename, content_type: input.content_type)
    input.verify_stored!(@pending_blob)
  end

  def inspect_staged!(request, input)
    stage!(input)
    JrcContactCenter::AudioSafetyObservation.new(access: @access).receive!(unit_id: request.unit_id, blob: @pending_blob, input: input)
  end

  def persist_or_replay!(request, input, digest, observation)
    asset = current_origin!(request)
    existing = replay!(request, digest)
    return existing if existing

    check_revision!(asset, request)
    asset ||= JrcContactCenter::AudioAsset.create!(request.attributes.merge('account' => @access.account,
                                                                            'unit' => @access.unit(request.unit_id)))
    version = JrcContactCenter::AudioVersion.create!(version_attributes(asset, request, input, digest))
    JrcContactCenter::AudioInspections.new(access: @access).record_received!(version: version, upload_key: request.key, attributes: observation)
    request.origin&.record_copy!(version)
    version
  end

  def version_attributes(asset, request, input, digest)
    input.version_attributes.merge(account: @access.account, unit_id: asset.unit_id, audio_asset: asset,
                                   blob: @pending_blob, created_by: @access.actor, source_kind: request.source_kind,
                                   number: @access.versions(asset).maximum(:number).to_i + 1,
                                   idempotency_key: request.key, input_digest: digest)
  end
end

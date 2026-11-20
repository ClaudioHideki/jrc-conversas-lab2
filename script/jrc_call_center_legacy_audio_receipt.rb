# frozen_string_literal: true

require_relative 'jrc_call_center_audio_storage_guard'
require 'digest'
require 'json'

# Historical quarantine fixture only. Not a live upload route, scanner proof or production migration.
class JrcContactCenter::SyntheticLegacyAudioReceipt
  def initialize(access:)
    @access = access
  end

  def create!(unit_id:, attributes:, file:, key:)
    JrcContactCenter::SyntheticAudioStorageGuard.call
    @access.refresh!
    unit = @access.unit(unit_id)
    values = JrcContactCenter::AudioAssetAttributes.parse(attributes)
    values['folder_id'] = @access.folder(values['folder_id'], unit: unit)&.id&.to_s
    input = JrcContactCenter::AudioFileInput.new(file: file)
    blob = JrcContactCenter::PrivateAudioBlob.upload(file: input.file, filename: input.filename, content_type: input.content_type)
    input.verify_stored!(blob)
    @access.transaction { persist!(unit, values, input, blob, key) }
  rescue StandardError
    JrcContactCenter::PrivateAudioBlob.clean_uncommitted(blob)
    raise
  end

  private

  def persist!(unit, values, input, blob, key)
    @access.unit(unit.id)
    @access.folder(values['folder_id'], unit: unit)
    asset = JrcContactCenter::AudioAsset.create!(values.merge('account' => @access.account, 'unit' => unit))
    attributes = input.version_attributes.merge(
      account: @access.account, unit_id: unit.id, audio_asset: asset, blob: blob, created_by: @access.actor,
      source_kind: 'user_upload', number: 1, idempotency_key: key, input_digest: input_digest(unit, values, input)
    )
    JrcContactCenter::AudioVersion.create!(attributes)
  end

  def input_digest(unit, values, input)
    fields = [@access.account.id.to_s, @access.actor.id.to_s, unit.id.to_s, nil,
              values.sort.to_h, input.filename, input.content_type, input.byte_size, input.sha256]
    Digest::SHA256.hexdigest(JSON.generate(fields))
  end
end

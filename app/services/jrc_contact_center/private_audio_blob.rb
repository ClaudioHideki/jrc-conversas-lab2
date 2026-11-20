# frozen_string_literal: true

# Native storage mechanism; a locator is never an authorization to institutional bytes.
class JrcContactCenter::PrivateAudioBlob
  MARKER = 'jrc_contact_center_institutional_audio'

  def self.upload(file:, filename:, content_type:)
    file.tempfile.rewind
    JrcBackoffice::PrivateBlob.upload_owned(io: file.tempfile, filename: filename, content_type: content_type, marker: MARKER)
  end

  def self.protected?(blob)
    owned?(blob) || JrcContactCenter::AudioVersion.exists?(blob_id: blob.id)
  end

  def self.clean_uncommitted(blob)
    return unless blob && owned?(blob)
    return if JrcContactCenter::AudioVersion.uncached { JrcContactCenter::AudioVersion.exists?(blob_id: blob.id) }

    JrcBackoffice::PrivateBlob.clean_uncommitted(blob, marker: MARKER)
  rescue StandardError => error
    Rails.logger.warn("contact_center_owned_audio_cleanup_pending class=#{error.class.name}")
  end

  def self.owned?(blob)
    blob.metadata.is_a?(Hash) && blob.metadata[MARKER] == true
  end
end

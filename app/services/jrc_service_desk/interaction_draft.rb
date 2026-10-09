# frozen_string_literal: true

class JrcServiceDesk::InteractionDraft
  attr_reader :values, :body, :key, :audience, :destinations, :uploads, :fingerprint, :preview_receipt

  def initialize(attributes:, files:, idempotency_key:, preview_receipt:)
    @values = JrcServiceDesk::Input.attributes(attributes, JrcServiceDesk::AddNoteService::FIELDS)
    @body = values['body']
    raise ArgumentError, 'Expected text' unless body.is_a?(String)

    @key = JrcServiceDesk::Input.request_key(idempotency_key)
    @audience = JrcServiceDesk::InteractionVisibility.attributes(values)
    @destinations = normalize_destinations
    @audience[:notification_state] = 'requested' if audience[:notification_channels].any?
    @uploads = JrcServiceDesk::InteractionAttachments.prepare(files)
    @fingerprint = JrcServiceDesk::CanonicalJson.digest(fingerprint_values)
    @preview_receipt = preview_receipt
  end

  def file_fingerprints
    uploads.map { |file| file.except(:io).stringify_keys }
  end

  private

  def normalize_destinations
    destinations = values.fetch('notification_conversations', {})
    unless destinations.is_a?(Hash) && (destinations.keys - audience[:notification_channels]).empty?
      raise ArgumentError, 'Explicit channel destinations required'
    end

    destinations.transform_values { |id| JrcServiceDesk::Input.id(id) }
  end

  def fingerprint_values
    # Preserve replay keys of all legacy internal notes.
    original = values.except('body').empty? ? { 'body' => body } : values.merge('body' => body)
    uploads.any? ? original.merge('files' => file_fingerprints) : original
  end
end

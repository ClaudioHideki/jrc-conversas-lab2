# frozen_string_literal: true

# Metadata-only selection. Identifiers and revision tokens never grant access.
class JrcContactCenter::AudioMoveInput
  MAX_ENTRIES = 20
  KEYS = %w[audio_asset_id expected_revision].freeze

  def initialize(access:)
    @access = access
  end

  def call(items)
    invalid! unless items.is_a?(Array) && items.length.between?(1, MAX_ENTRIES)
    rows = items.map { |row| normalize(row) }
    invalid! unless rows.pluck('audio_asset_id').uniq.length == rows.length
    rows.freeze
  end

  private

  def normalize(value)
    row = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value
    invalid! unless row.is_a?(Hash) && row.stringify_keys.keys.sort == KEYS.sort
    row = row.stringify_keys
    id = @access.identifier!(row.fetch('audio_asset_id')).dup.freeze
    revision = row.fetch('expected_revision')
    { 'audio_asset_id' => id, 'expected_revision' => revision.is_a?(String) ? revision.dup.freeze : revision }.freeze
  end

  def invalid!
    raise JrcContactCenter::OperationError, 'invalid_institutional_audio_move'
  end
end

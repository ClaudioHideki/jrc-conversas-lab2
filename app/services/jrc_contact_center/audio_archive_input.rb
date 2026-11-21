# frozen_string_literal: true

class JrcContactCenter::AudioArchiveInput
  MAX_ENTRIES = 20
  MAX_TOTAL_BYTES = 40.megabytes
  IDS = %w[audio_asset_id audio_version_id inspection_id].freeze
  KEYS = (IDS + ['sha256']).freeze

  def self.limits
    { max_entries: MAX_ENTRIES, max_bytes: [MAX_TOTAL_BYTES, JrcContactCenter::AudioFileInput.max_bytes].min }
  end

  def initialize(access:)
    @access = access
  end

  def call(items)
    invalid! unless items.is_a?(Array) && items.length.between?(1, MAX_ENTRIES)
    rows = items.map { |item| normalized(item) }
    identities = rows.map { |row| row.values_at('audio_asset_id', 'audio_version_id') }
    invalid! unless identities.uniq.length == rows.length
    rows.freeze
  end

  private

  def normalized(value)
    row = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value
    invalid! unless row.is_a?(Hash)
    row = row.stringify_keys
    invalid! unless row.keys.sort == KEYS.sort && row['sha256'].is_a?(String) && row['sha256'].match?(/\A[a-f0-9]{64}\z/)
    ids = IDS.index_with { |key| @access.identifier!(row.fetch(key)).dup.freeze }
    ids.merge('sha256' => row.fetch('sha256').dup.freeze).freeze
  end

  def invalid!
    raise JrcContactCenter::OperationError, 'invalid_institutional_audio_archive'
  end
end

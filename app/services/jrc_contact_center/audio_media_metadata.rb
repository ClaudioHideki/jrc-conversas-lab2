# frozen_string_literal: true

require 'bigdecimal'

# Only the explicitly requested container/stream fields are retained; no tags, filename or locator.
class JrcContactCenter::AudioMediaMetadata
  TYPES = {
    'wav' => 'audio/wav', 'mp3' => 'audio/mpeg', 'ogg' => 'audio/ogg',
    'mov,mp4,m4a,3gp,3g2,mj2' => 'audio/mp4', 'matroska,webm' => 'audio/webm'
  }.freeze
  FIELDS = %w[container codec content_type duration_ms sample_rate channels probe_version].freeze

  def self.valid?(metadata)
    return false unless metadata.is_a?(Hash) && metadata.keys.all?(String) && metadata.keys.sort == FIELDS.sort

    valid_text?(metadata) && valid_numbers?(metadata) && TYPES[metadata['container']] == metadata['content_type']
  end

  def self.extract(document, version:)
    return unless document.is_a?(Hash)

    stream = audio_stream(document.fetch('streams'))
    format = document.fetch('format')
    return unless stream && format.is_a?(Hash)

    metadata = stream_metadata(stream, format, version)
    valid?(metadata) ? metadata : nil
  rescue KeyError
    nil
  end

  def self.audio_stream(streams)
    return unless streams.is_a?(Array) && streams.length == 1 && streams.first.is_a?(Hash)

    stream = streams.first
    stream if stream['codec_type'] == 'audio'
  end

  def self.stream_metadata(stream, format, version)
    { 'container' => format['format_name'], 'codec' => stream['codec_name'],
      'content_type' => TYPES[format['format_name']], 'probe_version' => version,
      'sample_rate' => integer(stream['sample_rate']), 'channels' => integer(stream['channels']),
      'duration_ms' => duration(stream['duration']) || duration(format['duration']) }
  end

  def self.valid_text?(metadata)
    valid = %w[container codec content_type probe_version].all? do |key|
      metadata[key].is_a?(String) && metadata[key].present? && metadata[key].length <= 200
    end
    valid && metadata['probe_version'].start_with?('ffprobe version ')
  end

  def self.valid_numbers?(metadata)
    positive = %w[duration_ms sample_rate channels].all? { |key| metadata[key].is_a?(Integer) && metadata[key].positive? }
    positive && metadata['duration_ms'] <= 9_223_372_036_854_775_807 &&
      metadata['sample_rate'] <= 2_147_483_647 && metadata['channels'] <= 2_147_483_647
  end

  def self.integer(value)
    return unless (value.is_a?(String) || value.is_a?(Integer)) && value.to_s.match?(/\A[0-9]{1,10}\z/)

    value.to_i
  end

  def self.duration(value)
    return unless value.is_a?(String) || value.is_a?(Numeric)

    decimal = BigDecimal(value.to_s, exception: false)
    return unless decimal&.finite? && decimal.positive? && decimal <= BigDecimal('9223372036854775.807')

    (decimal * 1000).round.to_i
  end
  private_class_method :integer, :duration, :audio_stream, :stream_metadata, :valid_text?, :valid_numbers?
end

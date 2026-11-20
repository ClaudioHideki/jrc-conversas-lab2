# frozen_string_literal: true

require 'digest'
require 'time'
require 'timeout'

# Internal observation only; this grants no byte access and does not publish or mark a version ready.
class JrcContactCenter::AudioSafetyObservation
  Result = Struct.new(:version, :attributes, keyword_init: true)
  Deadline = Class.new(StandardError)
  ADAPTER = 'clamav-instream-v1'

  def initialize(access:, scanner: JrcServiceDesk::AttachmentScanner.new, probe: JrcContactCenter::AudioMediaProbe.new)
    @access = access
    @scanner = scanner
    @probe = probe
  end

  def call(asset_id:, version_id:)
    version = @access.transaction { selected_version(asset_id, version_id) }
    attributes = bounded_inspection(version)
    @access.transaction do
      current = selected_version(asset_id, version_id)
      raise JrcContactCenter::OperationError, 'institutional_audio_integrity_failed' unless current.sha256 == version.sha256

      Result.new(version: current, attributes: attributes)
    end
  end

  private

  def bounded_inspection(version)
    Timeout.timeout(45, Deadline) { inspect_bytes(version) }
  rescue Deadline
    observation('unavailable', nil)
  end

  def selected_version(asset_id, version_id)
    asset = @access.asset(asset_id)
    @access.versions(asset).find(@access.identifier!(version_id))
  end

  def inspect_bytes(version)
    version.blob.open do |file|
      observed = Digest::SHA256.file(file.path).hexdigest
      return observation('checksum_mismatch', observed) unless observed == version.sha256

      scan_bytes(version, file, observed)
    end
  rescue ActiveStorage::IntegrityError
    observation('checksum_mismatch', nil)
  rescue ActiveStorage::FileNotFoundError, IOError, SystemCallError
    observation('unavailable', nil)
  end

  def scan_bytes(version, file, observed)
    scan = @scanner.scan(version.blob, socket_path: ENV.fetch('JRC_CC_AUDIO_CLAMAV_SOCKET', nil))
    return observation('unavailable', observed) unless valid_scan?(scan)
    return observation('checksum_mismatch', observed) unless scan['service_desk_scan_sha256'] == version.sha256

    state = scan.fetch('service_desk_scan_state')
    state == 'clean' ? probe_observation(version, file, observed) : observation(state, observed)
  end

  def valid_scan?(scan)
    scan.is_a?(Hash) && %w[clean infected].include?(scan['service_desk_scan_state']) &&
      scan['service_desk_scan_adapter'] == ADAPTER && scan['service_desk_scan_sha256'].to_s.match?(/\A[0-9a-f]{64}\z/) &&
      scan['service_desk_scanned_at'].is_a?(String) && Time.iso8601(scan['service_desk_scanned_at']).present?
  rescue ArgumentError
    false
  end

  def probe_observation(version, file, observed)
    result = @probe.call(file)
    return observation('clean', observed, probe_state: result.fetch(:state)) unless result[:state] == 'valid'

    metadata = result[:metadata]
    decoder = result[:decoder_version]
    valid = JrcContactCenter::AudioMediaMetadata.valid?(metadata) && metadata['content_type'] == version.content_type &&
            decoder.is_a?(String) && decoder.start_with?('ffmpeg version ') && decoder.length <= 200
    return observation('clean', observed, probe_state: 'unavailable') unless valid

    observation('clean', observed, probe_state: 'valid').merge(metadata: metadata, decoder_version: decoder)
  end

  def observation(state, observed, probe_state: 'not_run')
    { state: state, observed_sha256: observed, scanner_adapter: ADAPTER, observed_at: Time.current,
      probe_state: probe_state, metadata: {}, decoder_version: nil }
  end
end

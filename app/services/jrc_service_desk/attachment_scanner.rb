# frozen_string_literal: true

require 'socket'
require 'timeout'
require 'digest'

# Optional local ClamAV INSTREAM adapter. Only a configured local Unix socket
# is supported; no filename is interpolated into a shell and no remote URL is
# accepted. An unavailable/malformed scanner never releases a download.
class JrcServiceDesk::AttachmentScanner
  def scan(blob)
    path = ENV.fetch('JRC_SD_CLAMAV_SOCKET', nil)
    return { 'service_desk_scan_state' => 'unavailable' } if path.blank?
    raise ArgumentError unless path.start_with?('/run/', '/var/run/') && !path.include?("\0")

    Timeout.timeout(30) do
      blob.open do |file|
        digest = Digest::SHA256.file(file.path).hexdigest
        result = UNIXSocket.open(path) do |socket|
          socket.write("zINSTREAM\0")
          while (chunk = file.read(64 * 1024))
            socket.write([chunk.bytesize].pack('N'))
            socket.write(chunk)
          end
          socket.write([0].pack('N'))
          reply = socket.read(2049)
          if reply == "stream: OK\0"
            'clean'
          elsif reply&.match?(/\Astream: .+ FOUND\x00\z/)
            'infected'
          else
            'unavailable'
          end
        end
        { 'service_desk_scan_state' => result, 'service_desk_scan_sha256' => digest,
          'service_desk_scan_adapter' => 'clamav-instream-v1', 'service_desk_scanned_at' => Time.current.iso8601(6) }
      end
    end
  rescue ArgumentError, SystemCallError, IOError, Timeout::Error, ActiveStorage::IntegrityError
    { 'service_desk_scan_state' => 'unavailable' }
  end

  def self.download(blob)
    raise JrcServiceDesk::AttachmentScanError unless clean?(blob)

    blob.open do |file|
      raise JrcServiceDesk::AttachmentScanError unless Digest::SHA256.file(file.path).hexdigest == blob.metadata['service_desk_scan_sha256']

      file.read
    end
  rescue ActiveStorage::IntegrityError
    raise JrcServiceDesk::AttachmentScanError
  end

  def self.clean?(blob)
    metadata = blob.metadata
    metadata['service_desk_scan_state'] == 'clean' && metadata['service_desk_scan_adapter'] == 'clamav-instream-v1' &&
      metadata['service_desk_scan_sha256'].to_s.match?(/\A[a-f0-9]{64}\z/) && metadata['service_desk_scanned_at'].present?
  end
end

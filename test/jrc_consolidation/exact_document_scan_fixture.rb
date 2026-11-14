raise 'Synthetic scan fixture requires Rails test environment' unless defined?(Rails) && Rails.env.test?

require_relative 'candidate_fixture_scanner'

module ExactDocumentScanFixture
  private

  # Real INSTREAM transport and durable scan receipt, with a synthetic daemon
  # that accepts only this fixture's exact checksum. This is not antivirus
  # homologation and never changes the application's quarantine policy.
  def scan_synthetic_document!(version)
    previous_socket = ENV['JRC_BO_CLAMAV_SOCKET']
    path = "#{ENV.fetch('JRC_BO_TEST_SOCKET_DIRECTORY', '/run')}/jrc-workspace-av-#{SecureRandom.hex(8)}.sock"
    server = UNIXServer.new(path)
    worker = Thread.new do
      peer = server.accept
      begin
        peer.write(CandidateFixtureScanner.reply(peer, [version.sha256]))
      ensure
        peer.close
      end
    end
    ENV['JRC_BO_CLAMAV_SOCKET'] = path
    scan = JrcBackoffice::DocumentSafety.new(version).scan!
    Timeout.timeout(10) { worker.value }
    assert scan.clean?, "Synthetic fixture was not scanned: #{scan.state}"
    assert_equal version.sha256, scan.observed_sha256
    assert_equal version.file.blob.id, scan.source_blob_id
  ensure
    ENV['JRC_BO_CLAMAV_SOCKET'] = previous_socket
    worker&.kill if worker&.alive?
    server&.close
    File.unlink(path) if path && File.socket?(path)
  end
end

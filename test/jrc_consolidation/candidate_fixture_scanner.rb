# Test transport boundary only. This is NOT malware detection and is excluded from the image.
require 'digest'
require 'json'
require 'socket'
require 'timeout'

class CandidateFixtureScanner
  def self.reply(stream, allowed)
    Timeout.timeout(5) do
      return "stream: ERROR\0" unless stream.read(10) == "zINSTREAM\0"

      digest = Digest::SHA256.new
      total = 0
      loop do
        header = stream.read(4)
        return "stream: ERROR\0" unless header&.bytesize == 4

        size = header.unpack1('N')
        break if size.zero?

        total += size
        return "stream: ERROR\0" if size > 65_536 || total > 20 * 1024 * 1024

        bytes = stream.read(size)
        return "stream: ERROR\0" unless bytes&.bytesize == size

        digest.update(bytes)
      end
      allowed.include?(digest.hexdigest) ? "stream: OK\0" : "stream: Synthetic.NotAllowed FOUND\0"
    end
  rescue Timeout::Error, IOError
    "stream: ERROR\0"
  end
end

if $PROGRAM_NAME == __FILE__
  raise 'Exclusive synthetic candidate runtime required' unless ENV['GITHUB_ACTIONS'] == 'true' &&
    ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' && ENV['POSTGRES_DATABASE'] == 'backoffice_candidate_smoke_test' &&
    ENV.fetch('CANDIDATE_SHA', '').match?(/\A[a-f0-9]{40}\z/)

  directory = '/run/jrc-candidate-av'
  File.umask(0o077)
  server = UNIXServer.new("#{directory}/clamd.sock")
  loop do
    client = server.accept
    begin
      allowed = JSON.parse(File.read("#{directory}/synthetic-sha256.json"))
      raise 'Only an explicit small synthetic allowlist is accepted' unless allowed.is_a?(Array) &&
        allowed.length.between?(1, 2) && allowed.all? { |sha| sha.match?(/\A[a-f0-9]{64}\z/) }

      client.write(CandidateFixtureScanner.reply(client, allowed))
    rescue StandardError
      client.write("stream: ERROR\0")
    ensure
      client.close
    end
  end
end

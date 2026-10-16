require 'openssl'
require 'base64'
require 'digest'
require 'json'
require 'pathname'
require 'time'

class JrcFlows::OwnershipIdentity
  # Only the external observer holds the signing key. Application-owned
  # metadata and legacy config proofs are never deployment evidence.
  def self.verify!(request)
    root = Rails.root.realpath
    observation = Pathname.new(ENV.fetch('JRC_FLOW_OWNERSHIP_ATTESTATION_DIR'))
    raise JrcFlows::NativeOwnership::Denied unless observation.absolute?

    observation = observation.realpath
    guard_bytes = File.binread(contained_file!(root, 'config/jrc_flow_ownership_guards.json'))
    guard = JSON.parse(guard_bytes)
    signed = JSON.parse(File.read(contained_file!(observation, 'jrc_flow_ownership_attestation.json')))
    payload = signed.fetch('payload')
    key = OpenSSL::PKey.read(File.read(contained_file!(observation, 'jrc_flow_ownership_attestation_public.pem')))
    signature = Base64.strict_decode64(signed.fetch('signature'))
    raise JrcFlows::NativeOwnership::Denied unless key.respond_to?(:oid) && key.oid == 'ED25519' && key.verify(nil, signature, JSON.generate(payload))

    now = ApplicationRecord.connection.select_value('SELECT clock_timestamp()').to_time
    observed = Time.iso8601(payload.fetch('observedAt'))
    expires = Time.iso8601(payload.fetch('expiresAt'))
    raise JrcFlows::NativeOwnership::Denied unless observed <= now && expires > now && expires <= observed + 300 && now - observed <= 300
    raise JrcFlows::NativeOwnership::Denied unless payload['hostSourceSha'] == request['expectedHostSourceSha'] &&
                                                   payload['hostImageDigest'] == request['expectedHostImageDigest'] &&
                                                   payload['guardManifestSha256'] == Digest::SHA256.hexdigest(guard_bytes)
    raise JrcFlows::NativeOwnership::Denied unless /\A[A-Za-z0-9_-]{43}\z/.match?(payload['observationNonce'].to_s)
    raise JrcFlows::NativeOwnership::Denied unless measured_processes?(payload, observed, now)

    paths = JrcFlows::OwnershipGuard::PATHS
    raise JrcFlows::NativeOwnership::Denied unless guard.fetch('paths').sort == paths.keys.sort

    guard.fetch('files').each do |relative, hash|
      actual = contained_file!(root, relative)
      raise JrcFlows::NativeOwnership::Denied unless /\A[a-f0-9]{64}\z/.match?(hash.to_s) && Digest::SHA256.file(actual).hexdigest == hash
    end
    raise JrcFlows::NativeOwnership::Denied unless paths.values.all? { |file| guard['files'].key?(file) }

    { source: payload['hostSourceSha'], image: payload['hostImageDigest'], paths: paths.keys }
  rescue StandardError
    raise JrcFlows::NativeOwnership::Denied, 'FLOW_HOST_INSTALLED_IDENTITY_REQUIRED'
  end

  def self.measured_processes?(payload, observed, now)
    processes = payload.fetch('workers')
    return false unless processes.is_a?(Array) && processes.any?

    identities = []
    roles = []
    stamps = []
    valid = processes.all? do |process|
      next false unless process.is_a?(Hash) && process['observed'] == true &&
                        /\A[a-f0-9]{64}\z/.match?(process['containerId'].to_s) &&
                        process['pid'].is_a?(Integer) && process['pid'].positive? &&
                        /\A[0-9]+\z/.match?(process['processStartTicks'].to_s) &&
                        %w[rails worker].include?(process['role']) &&
                        process['imageDigest'] == payload['hostImageDigest'] &&
                        process['guardManifestSha256'] == payload['guardManifestSha256']

      stamp = Time.iso8601(process.fetch('observedAt'))
      identities << [process['containerId'], process['pid']]
      roles << process['role']
      stamps << stamp
      stamp >= observed && stamp <= now && now - stamp <= 300
    end
    # The observer serializes its oldest microsecond SQL stamp as ISO millis.
    valid && identities.uniq.length == processes.length && %w[rails worker].all? { |role| roles.include?(role) } &&
      stamps.min - observed < 0.001
  end
  private_class_method :measured_processes?

  def self.contained_file!(root, relative)
    candidate = root.join(relative).cleanpath.realpath
    unless candidate.to_s.start_with?(root.to_s + '/') && candidate.file? && (candidate.stat.mode & 0o022).zero?
      raise JrcFlows::NativeOwnership::Denied
    end

    candidate
  end
  private_class_method :contained_file!
end

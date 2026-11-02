# Fixture certificates only. This entrypoint does not load Rails or contact a service.
require 'openssl'
require 'securerandom'
require 'tmpdir'
require 'json'

directory = File.realpath(ARGV.fetch(0))
unless directory.start_with?(File.realpath(Dir.tmpdir) + File::SEPARATOR) && File.basename(directory).start_with?('broker_https_')
  abort 'LAB_CERTIFICATE_DIRECTORY_REQUIRED'
end
abort 'LAB_CERTIFICATES_ALREADY_EXIST' if File.exist?(File.join(directory, 'ca-key.pem'))

# Keep X509 extensions visible in one fixture builder; it never loads Rails or changes OS trust.
# rubocop:disable Metrics/AbcSize, Metrics/MethodLength
def fixture_certificate(key, name, issuer: nil, issuer_key: nil, authority: false)
  certificate = OpenSSL::X509::Certificate.new
  certificate.version = 2
  certificate.serial = SecureRandom.random_number(2**120) + 1
  certificate.subject = OpenSSL::X509::Name.parse("/CN=#{name}")
  certificate.issuer = issuer ? issuer.subject : certificate.subject
  certificate.public_key = key.public_key
  certificate.not_before = Time.now.utc - 60
  certificate.not_after = Time.now.utc + 86_400
  extensions = OpenSSL::X509::ExtensionFactory.new
  extensions.subject_certificate = certificate
  extensions.issuer_certificate = issuer || certificate
  certificate.add_extension(extensions.create_extension('basicConstraints', authority ? 'CA:TRUE' : 'CA:FALSE', true))
  certificate.add_extension(extensions.create_extension('keyUsage', authority ? 'keyCertSign,cRLSign' : 'digitalSignature,keyEncipherment', true))
  certificate.add_extension(extensions.create_extension('subjectKeyIdentifier', 'hash'))
  unless authority
    certificate.add_extension(extensions.create_extension('extendedKeyUsage', 'serverAuth'))
    certificate.add_extension(extensions.create_extension('subjectAltName', "DNS:#{name}"))
  end
  certificate.sign(issuer_key || key, OpenSSL::Digest.new('SHA256'))
  certificate
end
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength

authority_key = OpenSSL::PKey::RSA.new(2048)
authority = fixture_certificate(authority_key, 'JRC HTTPS fixture CA', authority: true)
server_key = OpenSSL::PKey::RSA.new(2048)
server = fixture_certificate(server_key, 'broker-https-lab.test', issuer: authority, issuer_key: authority_key)
wrong_host = fixture_certificate(server_key, 'wrong-host.broker-https-lab.test', issuer: authority, issuer_key: authority_key)
wrong_authority_key = OpenSSL::PKey::RSA.new(2048)
wrong_authority = fixture_certificate(wrong_authority_key, 'Untrusted JRC HTTPS fixture CA', authority: true)
{
  'ca-key.pem' => authority_key.to_pem, 'ca.pem' => authority.to_pem,
  'server-key.pem' => server_key.to_pem, 'server.pem' => server.to_pem,
  'wrong-host.pem' => wrong_host.to_pem, 'wrong-ca.pem' => wrong_authority.to_pem
}.each do |filename, value|
  File.open(File.join(directory, filename), File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(value) }
end
puts JSON.generate(fixture_certificates: true, ca_sha256: OpenSSL::Digest::SHA256.hexdigest(authority.to_der), validity_seconds: 86_400)

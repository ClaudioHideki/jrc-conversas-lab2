require 'json'
require 'uri'
require 'digest'
require 'tmpdir'

module BrokerHttpsHarness
  class ValidationError < StandardError; end

  ORIGIN = 'https://broker-https-lab.test'.freeze
  DATABASES = { 'a' => 'jrc_broker_https_a_test', 'b' => 'jrc_broker_https_b_test' }.freeze
  ID_FIELDS = %w[account_id inbox_id message_id conversation_id].freeze
  UUID_FIELDS = %w[organization_id integration_id instance_id delivery_id].freeze
  LINEAGE_FIELDS = %w[delivery_id integration_id body_sha256].freeze
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

  # Keep the independent fixture boundaries explicit and together for safety review.
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def self.runtime!(environment)
    fail!('LAB_ONLY') unless environment['BROKER_HTTPS_LAB'] == '1' && environment['RAILS_ENV'] == 'test'
    key = DATABASES.key(environment['POSTGRES_DATABASE'])
    fail!('UNEXPECTED_LAB_DATABASE') unless key
    fail!('UNEXPECTED_LAB_ORIGIN') unless environment['BROKER_HTTPS_ORIGIN'] == ORIGIN
    fail!('PRIVATE_NETWORK_OPT_IN_REQUIRED') unless environment['SAFE_FETCH_ALLOW_PRIVATE_NETWORK'] == 'true'
    redis = URI(environment.fetch('REDIS_URL', ''))
    redis_path = key == 'a' ? '/0' : '/1'
    unless redis.scheme == 'redis' && redis.host == 'broker-https-redis' && redis.port == 6379 && redis.path == redis_path
      fail!('UNEXPECTED_LAB_REDIS')
    end

    directory = File.realpath(environment.fetch('BROKER_HTTPS_DIRECTORY', ''))
    temporary_root = File.realpath(Dir.tmpdir) + File::SEPARATOR
    fail!('UNEXPECTED_LAB_DIRECTORY') unless directory.start_with?(temporary_root) && File.basename(directory).start_with?('broker_https_')
    ca = File.realpath(environment.fetch('SSL_CERT_FILE', ''))
    fail!('UNEXPECTED_LAB_CA') unless ca.start_with?(directory + File::SEPARATOR) && File.file?(ca)
    { 'key' => key, 'queue' => "broker_https_homologation_#{key}", 'database' => DATABASES.fetch(key),
      'origin' => ORIGIN, 'directory' => directory, 'ca_file' => ca }.freeze
  rescue URI::InvalidURIError, KeyError, Errno::ENOENT
    fail!('INVALID_LAB_CONFIGURATION')
  end

  def self.contexts!(contexts)
    # Standalone Ruby arrays: ActiveSupport is intentionally not loaded by this guard.
    # rubocop:disable Rails/Pluck
    fail!('TWO_INDEPENDENT_CONTEXTS_REQUIRED') unless contexts.is_a?(Array) && contexts.size == 2 && contexts.map { |row| row['key'] }.sort == %w[a b]
    # rubocop:enable Rails/Pluck
    contexts.each do |row|
      fail!('UNEXPECTED_LAB_DATABASE') unless DATABASES.fetch(row['key']) == row['database']
      fail!('INVALID_LOCAL_IDENTIFIERS') unless ID_FIELDS.all? { |field| row[field].is_a?(Integer) && row[field].positive? }
      fail!('INVALID_SCOPED_IDENTIFIERS') unless UUID_FIELDS.all? { |field| UUID.match?(row[field].to_s) }
      fail!('INVALID_BODY_HASH') unless /\A[0-9a-f]{64}\z/.match?(row['body_sha256'].to_s)
    end
    ID_FIELDS.each { |field| fail!('LOCAL_IDENTIFIERS_MUST_COLLIDE') unless contexts.map { |row| row[field] }.uniq.size == 1 }
    UUID_FIELDS.each { |field| fail!('TENANT_IDENTIFIERS_MUST_DIFFER') unless contexts.map { |row| row[field] }.uniq.size == 2 }
    contexts
  end

  def self.verify!(context, broker_counts:, wire_requests:, obligation:)
    unless %w[organization_id integration_id].all? { |field| broker_counts[field] == context[field] } &&
           broker_counts['observations'] == 1 && broker_counts['reply_jobs'] == 1 && broker_counts['cross_tenant_observations'] == 0
      fail!('BROKER_CUSTODY_COUNT_OR_TENANT_MISMATCH')
    end
    revision = context.fetch('destination_revision', 1)
    job_key = "reply:#{revision}:#{context.fetch('account_id')}:#{context.fetch('inbox_id')}:#{context.fetch('message_id')}"
    unless broker_counts['event_key'] == "message:#{context.fetch('message_id')}" && broker_counts['job_dedupe_key'] == job_key
      fail!('BROKER_DEDUPE_SCOPE_MISMATCH')
    end
    unless wire_requests.is_a?(Array) && wire_requests.any? && wire_requests.all? do |request|
      LINEAGE_FIELDS.all? { |field| request[field] == context[field] }
    end
      fail!('PRODUCER_DELIVERY_LINEAGE_CHANGED')
    end
    unless obligation['state'] == 'delivered' &&
           %w[delivery_id account_id inbox_id message_id].all? { |field| obligation[field] == context[field] }
      fail!('PRODUCER_OBLIGATION_NOT_CONFIRMED')
    end
    true
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  def self.write_json!(directory, filename, value)
    fail!('INVALID_LAB_FILENAME') unless /\A[a-z0-9_-]+\.json\z/.match?(filename)
    target = File.join(directory, filename)
    temporary = "#{target}.#{Process.pid}.tmp"
    File.open(temporary, 'wb', 0o600) { |file| file.write(JSON.pretty_generate(value)) }
    File.rename(temporary, target)
    target
  end

  def self.fail!(code)
    raise ValidationError, code
  end
end

# Pure Ruby guard/proof tests. No Rails, Sidekiq, Redis, HTTP or Docker stack is started.
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'securerandom'
require_relative 'broker_https_harness'

class BrokerHttpsHarnessTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir('broker_https_')
    @ca = File.join(@directory, 'ca.pem')
    File.write(@ca, 'Unit-only path sentinel; TLS is verified by the real socket harness, not this unit test.')
    @environment = {
      'BROKER_HTTPS_LAB' => '1', 'RAILS_ENV' => 'test', 'POSTGRES_DATABASE' => 'jrc_broker_https_a_test',
      'BROKER_HTTPS_ORIGIN' => 'https://broker-https-lab.test', 'SAFE_FETCH_ALLOW_PRIVATE_NETWORK' => 'true',
      'SSL_CERT_FILE' => @ca, 'BROKER_HTTPS_DIRECTORY' => @directory, 'REDIS_URL' => 'redis://broker-https-redis:6379/0'
    }
    @contexts = %w[a b].map do |key|
      { 'key' => key, 'database' => "jrc_broker_https_#{key}_test", 'account_id' => 1, 'inbox_id' => 1, 'message_id' => 1,
        'conversation_id' => 1, 'organization_id' => SecureRandom.uuid, 'integration_id' => SecureRandom.uuid,
        'instance_id' => SecureRandom.uuid, 'delivery_id' => SecureRandom.uuid, 'body_sha256' => 'a' * 64 }
    end
    @context = @contexts.first
    @counts = { 'organization_id' => @context['organization_id'], 'integration_id' => @context['integration_id'],
                'observations' => 1, 'reply_jobs' => 1, 'event_key' => 'message:1', 'job_dedupe_key' => 'reply:1:1:1:1',
                'cross_tenant_observations' => 0 }
    @wire = [{ 'delivery_id' => @context['delivery_id'], 'integration_id' => @context['integration_id'], 'body_sha256' => 'a' * 64 }]
    @obligation = { 'state' => 'delivered', 'delivery_id' => @context['delivery_id'], 'account_id' => 1, 'inbox_id' => 1, 'message_id' => 1 }
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_accepts_only_the_explicit_fixture_runtime
    result = BrokerHttpsHarness.runtime!(@environment)
    assert_equal 'a', result.fetch('key')
    assert_equal 'broker_https_homologation_a', result.fetch('queue')
  end

  def test_rejects_a_non_test_environment
    assert_raises(BrokerHttpsHarness::ValidationError) { BrokerHttpsHarness.runtime!(@environment.merge('RAILS_ENV' => 'production')) }
  end

  def test_rejects_an_unlisted_database_and_non_fixture_redis
    assert_raises(BrokerHttpsHarness::ValidationError) do
      BrokerHttpsHarness.runtime!(@environment.merge('POSTGRES_DATABASE' => 'jrc_durable_review_test'))
    end
    assert_raises(BrokerHttpsHarness::ValidationError) { BrokerHttpsHarness.runtime!(@environment.merge('REDIS_URL' => 'redis://localhost:6379/0')) }
  end

  def test_uses_distinct_redis_databases_for_the_two_independent_consumers
    other = @environment.merge('POSTGRES_DATABASE' => 'jrc_broker_https_b_test', 'REDIS_URL' => 'redis://broker-https-redis:6379/1')
    assert_equal 'b', BrokerHttpsHarness.runtime!(other).fetch('key')
    assert_raises(BrokerHttpsHarness::ValidationError) do
      BrokerHttpsHarness.runtime!(other.merge('REDIS_URL' => 'redis://broker-https-redis:6379/0'))
    end
  end

  def test_rejects_an_alternate_origin_or_implicit_private_network_opt_in
    assert_raises(BrokerHttpsHarness::ValidationError) { BrokerHttpsHarness.runtime!(@environment.merge('BROKER_HTTPS_ORIGIN' => 'http://broker-https-lab.test')) }
    assert_raises(BrokerHttpsHarness::ValidationError) do
      BrokerHttpsHarness.runtime!(@environment.merge('SAFE_FETCH_ALLOW_PRIVATE_NETWORK' => 'false'))
    end
  end

  def test_rejects_missing_or_external_ca_paths
    assert_raises(BrokerHttpsHarness::ValidationError) { BrokerHttpsHarness.runtime!(@environment.merge('SSL_CERT_FILE' => '/etc/ssl/cert.pem')) }
    File.unlink(@ca)
    assert_raises(BrokerHttpsHarness::ValidationError) { BrokerHttpsHarness.runtime!(@environment) }
  end

  def test_accepts_real_identifier_collisions_only_between_distinct_contexts
    assert_equal @contexts, BrokerHttpsHarness.contexts!(@contexts)
    bad = JSON.parse(JSON.generate(@contexts))
    bad.last['organization_id'] = bad.first['organization_id']
    assert_raises(BrokerHttpsHarness::ValidationError) { BrokerHttpsHarness.contexts!(bad) }
    bad.last['organization_id'] = SecureRandom.uuid
    bad.last['message_id'] = 2
    assert_raises(BrokerHttpsHarness::ValidationError) { BrokerHttpsHarness.contexts!(bad) }
  end

  def test_requires_one_real_observation_and_reply_job_for_the_correct_scope
    assert BrokerHttpsHarness.verify!(@context, broker_counts: @counts, wire_requests: @wire, obligation: @obligation)
    assert_raises(BrokerHttpsHarness::ValidationError) do
      BrokerHttpsHarness.verify!(@context, broker_counts: @counts.merge('reply_jobs' => 2), wire_requests: @wire, obligation: @obligation)
    end
    assert_raises(BrokerHttpsHarness::ValidationError) do
      BrokerHttpsHarness.verify!(@context, broker_counts: @counts.merge('organization_id' => @contexts.last['organization_id']),
                                           wire_requests: @wire, obligation: @obligation)
    end
  end

  def test_rejects_an_altered_delivery_hash_or_a_sender_not_settled_as_delivered
    assert_raises(BrokerHttpsHarness::ValidationError) do
      BrokerHttpsHarness.verify!(@context, broker_counts: @counts, wire_requests: @wire + [@wire.first.merge('body_sha256' => 'b' * 64)],
                                           obligation: @obligation)
    end
    assert_raises(BrokerHttpsHarness::ValidationError) do
      BrokerHttpsHarness.verify!(@context, broker_counts: @counts, wire_requests: @wire, obligation: @obligation.merge('state' => 'pending'))
    end
  end
end

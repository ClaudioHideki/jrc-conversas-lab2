require 'minitest/autorun'
require 'time'
module JrcBroker; end
require_relative '../../app/services/jrc_broker/origin_snapshot'

class JrcBrokerOriginSnapshotTest < Minitest::Test
  Binding = Struct.new(:integration_id, :instance_id, :inbox_id, :connection_state)
  def setup
    @binding = Binding.new('synthetic-integration', 'synthetic-instance', 11, {})
    @now = Time.iso8601('2026-11-05T12:01:00Z')
    @health = { 'integrationId' => @binding.integration_id, 'instanceId' => @binding.instance_id, 'inboxId' => 11,
                'identityApproved' => true, 'identityStatus' => 'CONFIRMED', 'identityRevision' => 2,
                'phoneNumber' => '+15550000001', 'checkedAt' => '2026-11-05T12:00:00Z', 'instanceStatus' => 'CONNECTED' }
  end

  def test_projection_exposes_only_verified_identity_and_no_provider_credentials
    snapshot = JrcBroker::OriginSnapshot.capture(@binding, @health.merge('credential' => 'not-public'))
    @binding.connection_state = { 'origin' => snapshot, 'health' => @health }
    assert_equal({ 'own_number' => '+15550000001', 'number_status' => 'VERIFIED', 'verified_at' => @health['checkedAt'], 'valid_until' => '2026-11-05T12:15:00Z' },
                 JrcBroker::OriginSnapshot.project(@binding, now: @now))
    refute_includes snapshot.to_s, 'not-public'
  end

  def test_missing_or_unconfirmed_number_is_not_inferred
    [nil, 'untrusted-url', '***0001'].each do |number|
      assert_nil JrcBroker::OriginSnapshot.capture(@binding, @health.merge('phoneNumber' => number))
    end
    assert_nil JrcBroker::OriginSnapshot.capture(@binding, @health.merge('identityApproved' => false))
    assert_nil JrcBroker::OriginSnapshot.capture(@binding, @health.except('checkedAt'))
  end

  def test_rebinding_invalidates_the_old_number_without_an_http_call
    snapshot = JrcBroker::OriginSnapshot.capture(@binding, @health)
    @binding.connection_state = { 'origin' => snapshot, 'health' => @health }
    @binding.integration_id = 'another-integration'
    assert_equal 'STALE', JrcBroker::OriginSnapshot.project(@binding, now: @now)['number_status']
    assert_nil JrcBroker::OriginSnapshot.project(@binding, now: @now)['own_number']
  end

  def test_delayed_identity_revision_does_not_authorize_a_number
    snapshot = JrcBroker::OriginSnapshot.capture(@binding, @health)
    @binding.connection_state = { 'origin' => snapshot, 'health' => @health.merge('identityRevision' => 3) }
    assert_equal 'STALE', JrcBroker::OriginSnapshot.project(@binding, now: @now)['number_status']
  end

  def test_an_unapproved_new_identity_hides_the_old_number
    snapshot = JrcBroker::OriginSnapshot.capture(@binding, @health)
    @binding.connection_state = { 'origin' => snapshot, 'health' => @health.merge('identityApproved' => false) }
    assert_nil JrcBroker::OriginSnapshot.project(@binding, now: @now)['own_number']
  end

  def test_future_or_malformed_snapshot_cannot_be_presented_as_verified
    snapshot = JrcBroker::OriginSnapshot.capture(@binding, @health)
    ['not-a-time', '2026-11-06T12:00:00Z'].each do |time|
      @binding.connection_state = { 'origin' => snapshot.merge('checkedAt' => time), 'health' => @health }
      assert_nil JrcBroker::OriginSnapshot.project(@binding, now: @now)['own_number']
    end
  end

  def test_conflicting_number_at_the_same_revision_stays_quarantined_until_the_revision_changes
    original = JrcBroker::OriginSnapshot.capture(@binding, @health)
    conflict = JrcBroker::OriginSnapshot.capture(@binding, @health.merge('phoneNumber' => '+15550000002'), previous: original)
    assert_equal true, conflict['conflict']
    repeated = JrcBroker::OriginSnapshot.capture(@binding, @health, previous: conflict)
    @binding.connection_state = { 'origin' => repeated, 'health' => @health }
    assert_nil JrcBroker::OriginSnapshot.project(@binding, now: @now)['own_number']
    resolved = JrcBroker::OriginSnapshot.capture(@binding, @health.merge('identityRevision' => 3), previous: conflict)
    refute resolved['conflict']
  end

  def test_an_expired_identity_is_stale_even_if_no_new_health_has_been_observed
    @binding.connection_state = { 'origin' => JrcBroker::OriginSnapshot.capture(@binding, @health), 'health' => @health }
    value = JrcBroker::OriginSnapshot.project(@binding, now: Time.iso8601('2026-11-05T12:15:01Z'))
    assert_equal 'STALE', value['number_status']
    assert_nil value['own_number']
  end

  def test_missing_number_does_not_erase_a_same_revision_conflict
    original = JrcBroker::OriginSnapshot.capture(@binding, @health)
    conflict = JrcBroker::OriginSnapshot.capture(@binding, @health.merge('phoneNumber' => '+15550000002'), previous: original)
    missing = JrcBroker::OriginSnapshot.capture(@binding, @health.except('phoneNumber'), previous: conflict)
    repeated = JrcBroker::OriginSnapshot.capture(@binding, @health.merge('phoneNumber' => '+15550000002'), previous: missing)
    assert_equal true, repeated['conflict']
    @binding.connection_state = { 'origin' => repeated, 'health' => @health }
    assert_nil JrcBroker::OriginSnapshot.project(@binding, now: @now)['own_number']
  end
end

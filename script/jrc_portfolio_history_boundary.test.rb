require 'minitest/autorun'
module JrcRelationship; end
require_relative '../app/services/jrc_relationship/portfolio_history_boundary'

class PortfolioHistoryBoundaryTest < Minitest::Test
  Proof = JrcRelationship::PortfolioHistoryBoundary
  def setup
    @snapshot = { 'version' => 1, 'account_id' => 1, 'group_id' => 3, 'event_digest' => 'a' * 64,
      'kind' => 'group', 'resolved' => true,
      'boundaries' => [{ 'owner_id' => 8, 'team_id' => 2, 'business_unit_id' => 4, 'segment_id' => 5, 'visibility' => 'private' }],
      'origins' => [{ 'id' => 7, 'company_id' => 19, 'contact_id' => nil, 'business_unit_id' => 4 }],
      'before' => { 'objective' => 'Historic customer goal' }, 'after' => { 'objective' => 'Revised customer goal' }, 'reason' => 'Explicit change' }
    @options = { account_id: 1, group_id: 3, actor_id: 8, admin: false, configure: false, team_ids: [2],
                 unit_allowed: ->(id) { id == 4 }, origins_allowed: ->(rows) { rows == @snapshot['origins'] }, references_allowed: ->(_) { true } }
  end
  def permitted(snapshot = @snapshot, **options)
    Proof.new(**@options.merge(options)).allowed?(snapshot, snapshot_digest: Proof.digest(snapshot), event_digest: 'a' * 64)
  end
  def test_original_owner_can_read_with_current_native_sources
    assert permitted
  end
  def test_sharing_later_does_not_expose_old_private_scope
    refute permitted(actor_id: 9, team_ids: [2])
  end
  def test_admin_still_needs_unit_scope
    refute permitted(admin: true, unit_allowed: ->(_) { false })
  end
  def test_admin_still_needs_every_historic_source
    refute permitted(admin: true, origins_allowed: ->(_) { false })
  end
  def test_revoked_roster_prevents_disclosure
    refute permitted(references_allowed: ->(_) { false })
  end
  def test_other_account_denied
    refute permitted(account_id: 2)
  end
  def test_other_group_denied
    refute permitted(group_id: 9)
  end
  def test_configuration_requires_current_configure_permission
    @snapshot.merge!('kind' => 'rules', 'before' => { 'version' => 0, 'rules' => {} }, 'after' => { 'version' => 1, 'rules' => { 'portfolio_transfer_approval_required' => true } })
    refute permitted
    assert permitted(configure: true)
  end
  def test_both_before_and_after_boundaries_required
    second = @snapshot['boundaries'].first.merge('owner_id' => 9, 'visibility' => 'private')
    @snapshot['boundaries'] << second
    refute permitted
    assert permitted(admin: true)
  end
  def test_current_team_permission_not_historic_membership_alone
    @snapshot['boundaries'][0]['visibility'] = 'team'
    assert permitted(actor_id: 9, team_ids: [2])
    refute permitted(actor_id: 9, team_ids: [])
  end
  def test_current_account_visibility_keeps_origin_checks
    @snapshot['boundaries'][0]['visibility'] = 'account'
    assert permitted(actor_id: 9, team_ids: [])
    refute permitted(actor_id: 9, origins_allowed: ->(_) { false })
  end
  def test_corrupted_digest_denied
    refute Proof.new(**@options).allowed?(@snapshot, snapshot_digest: '0' * 64, event_digest: 'a' * 64)
  end
  def test_changed_event_denied
    refute Proof.new(**@options).allowed?(@snapshot, snapshot_digest: Proof.digest(@snapshot), event_digest: 'b' * 64)
  end
  def test_digest_is_order_independent_for_hash_keys
    assert_equal Proof.digest(@snapshot), Proof.digest(@snapshot.to_a.reverse.to_h)
  end
  def test_digest_changes_for_changed_reason
    other = Marshal.load(Marshal.dump(@snapshot)); other['reason'] = 'Other reason'
    refute_equal Proof.digest(@snapshot), Proof.digest(other)
  end
  def test_empty_authorized_group_can_be_captured
    @snapshot['origins'] = []; assert permitted
  end
  def test_nested_customer_without_business_unit_requires_native_callback
    @snapshot['origins'][0]['business_unit_id'] = nil
    assert permitted
  end
  def test_null_unit_is_not_automatically_allowed
    @snapshot['boundaries'][0]['business_unit_id'] = nil
    refute permitted
    assert permitted(unit_allowed: ->(id) { id.nil? })
  end
  def test_duplicate_origin_does_not_dilute_authorization
    @snapshot['origins'] << @snapshot['origins'][0].dup
    refute permitted
  end
  def test_unresolved_scope_denied
    @snapshot['resolved'] = false; refute permitted
  end
  def test_wrong_version_denied
    @snapshot['version'] = 2; refute permitted
  end
  def test_empty_boundaries_denied
    @snapshot['boundaries'] = []; refute permitted
  end
  def test_two_customer_identities_denied
    @snapshot['origins'][0]['contact_id'] = 91; refute permitted
  end
  def test_absent_customer_identity_denied
    @snapshot['origins'][0]['company_id'] = nil; refute permitted
  end
  def test_unknown_visibility_denied
    @snapshot['boundaries'][0]['visibility'] = 'public'; refute permitted
  end
  def test_team_visibility_requires_team
    @snapshot['boundaries'][0].merge!('visibility' => 'team', 'team_id' => nil); refute permitted
  end
  def test_boundary_unknown_fields_denied
    @snapshot['boundaries'][0]['grant_all'] = true; refute permitted
  end
  def test_origin_unknown_fields_denied
    @snapshot['origins'][0]['private_name'] = 'Not part of a proof'; refute permitted
  end
  def test_false_ids_denied
    @snapshot['boundaries'][0]['owner_id'] = false; refute permitted
  end
  def test_string_ids_denied
    @snapshot['origins'][0]['id'] = '7'; refute permitted
  end
  def test_nil_snapshot_denied
    refute Proof.new(**@options).allowed?(nil, snapshot_digest: '', event_digest: '')
  end
  def test_overlong_reason_denied
    @snapshot['reason'] = 'a' * 4001; refute permitted
  end
  def test_blank_legacy_reason_allowed_without_fabrication
    @snapshot['reason'] = nil; assert permitted
  end
  def test_array_instead_of_value_object_denied
    @snapshot['before'] = []; refute permitted
  end
  def test_invalid_digest_field_denied
    @snapshot['event_digest'] = 'not a digest'; refute permitted
  end

  def test_unknown_top_level_payload_is_not_a_proof
    @snapshot['private_note'] = 'not part of audited schema'; refute permitted
  end
  def test_unapproved_raw_attribute_is_not_projected
    @snapshot['after']['sensitive_token'] = 'not allowed'; refute permitted
  end
  def test_unreferenced_historic_customer_denied
    @snapshot['after'] = { 'customers' => [[999, true]] }; refute permitted
  end
  def test_historic_customer_has_explicit_boolean_membership
    @snapshot['after'] = { 'customers' => [[7, true]] }; assert permitted
    @snapshot['after']['customers'][0][1] = 'true'; refute permitted
  end
  def test_unknown_goal_payload_denied
    @snapshot['after'] = { 'goals' => [{ 'metric' => 'test', 'secret' => 'no' }] }; refute permitted
  end
  def test_unknown_rule_payload_denied
    @snapshot.merge!('kind' => 'rules', 'before' => { 'rules' => {} }, 'after' => { 'rules' => { 'private_token' => 'no' } })
    refute permitted(configure: true)
  end
  def test_capacity_user_metadata_not_exposed
    @snapshot.merge!('kind' => 'rules', 'before' => { 'rules' => {} }, 'after' => { 'rules' => { 'portfolio_capacity_limits' => [{ 'user_id' => 8, 'secret' => 'no' }] } })
    refute permitted(configure: true)
  end
end

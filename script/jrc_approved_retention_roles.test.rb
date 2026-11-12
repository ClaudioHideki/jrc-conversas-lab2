require 'minitest/autorun'
require 'json'
module JrcRelationship; end
require_relative '../app/services/jrc_relationship/retention_policy'
require_relative '../app/services/jrc_relationship/retention_metric'
require_relative '../app/services/jrc_relationship/local_role_rules'

class ApprovedRetentionRulesTest < Minitest::Test
  P = JrcRelationship::RetentionPolicy
  M = JrcRelationship::RetentionMetric
  def policy
    { 'eligible_statuses' => %w[onboarding active at_risk], 'contact_mode' => 'registered_contact', 'target_percent' => nil }
  end
  def row(id, status = 'active', **extra)
    { 'customer_key' => "company:#{id}", 'customer_type' => 'company', 'source_present' => true,
      'master_active' => true, 'status' => status }.merge(extra.transform_keys(&:to_s))
  end
  def compute(opening, closing, **opts)
    M.call(opening: opening, closing: closing, policy: policy, complete: true, **opts)
  end
  def test_approved_example_100_to_92
    initial = (1..100).map { |id| row(id) }
    final = (1..100).map { |id| row(id, id <= 92 ? 'active' : 'inactive') }
    actual = compute(initial, final)
    assert_equal 92.0, actual[:value]
    assert_equal [100, 92, 8], actual.values_at(:initial, :retained, :exits)
  end
  def test_new_entrants_do_not_raise_the_metric_or_denominator
    assert_equal 50.0, compute([row(1), row(2)], [row(1), row(2,'churned'), row(3), row(4)])[:value]
    assert_equal 2, compute([row(1), row(2)], [row(1), row(2), row(3)])[:initial]
  end
  def test_real_zero_is_not_missing
    result = compute([row(1)], [row(1, 'inactive')]); assert result[:available]; assert_equal 0.0, result[:value]
  end
  def test_zero_denominator_is_not_zero_or_hundred
    result = compute([row(1, 'inactive')], [row(1)]); refute result[:available]; assert_nil result[:value]; assert_equal 'not_applicable', result[:code]
  end
  def test_no_opening_history_is_unavailable
    result = compute([], [row(1)]); refute result[:available]; assert_nil result[:value]
  end
  def test_incomplete_history_is_not_replaced_by_current_rows
    result = M.call(opening: [row(1)], closing: [row(1)], policy: policy, complete: false)
    assert_equal 'insufficient_history', result[:code]; assert_nil result[:initial]
  end
  def test_missing_closing_proof_does_not_mean_customer_lost
    result = compute([row(1), row(2)], [row(1)]); refute result[:available]; assert_nil result[:value]
  end
  def test_recorded_source_deletion_is_an_exit
    assert_equal 0.0, compute([row(1)], [row(1, source_present: false)])[:value]
  end
  def test_revocation_hides_even_cohort_counts
    result = compute([row(1)], [row(1)], authorized: false); assert_nil result[:initial]; assert_nil result[:retained]; assert_equal 'scope_unavailable', result[:code]
  end
  def test_master_inactive_is_exit_even_assignment_active
    assert_equal 0.0, compute([row(1)], [row(1, master_active: false)])[:value]
  end
  def test_unknown_master_state_is_not_guessed
    refute compute([row(1, master_active: nil)], [row(1)])[:available]
  end
  def test_duplicate_customers_are_rejected_not_counted_twice
    assert_equal 'ambiguous_history', compute([row(1), row(1)], [row(1)])[:code]
    assert_equal 'ambiguous_history', compute([row(1)], [row(1), row(1)])[:code]
  end
  def test_company_and_contact_same_id_are_different_native_entities
    a=row(1); b=row(1, customer_key: 'contact:1', customer_type: 'contact', registration_status: 'registered')
    assert_equal 2, compute([a,b],[a,b])[:initial]
  end
  def test_contact_registered_policy_is_explicit
    b=row(1, customer_key: 'contact:1', customer_type: 'contact', registration_status: 'provisional')
    assert_equal 'not_applicable', compute([b],[b])[:code]
    p=policy.merge('contact_mode'=>'relationship_status')
    assert_equal 100.0, M.call(opening:[b],closing:[b],policy:p,complete:true)[:value]
  end
  def test_unknown_type_is_unavailable
    refute compute([row(1,customer_type:'other')],[row(1)])[:available]
  end
  def test_exact_decimal_rounding
    assert_equal 66.67, compute([row(1),row(2),row(3)],[row(1),row(2),row(3,'inactive')])[:value]
  end
  def test_target_does_not_alter_score
    p=policy.merge('target_percent'=>99.5)
    result=M.call(opening:[row(1)],closing:[row(1,'inactive')],policy:p,complete:true)
    assert_equal 0.0,result[:value];assert_equal 99.5,result[:target_percent]
  end
  def test_inputs_are_not_mutated
    a=[row(1)];b=[row(1)];before=Marshal.dump([a,b]);compute(a,b);assert_equal before,Marshal.dump([a,b])
  end
  [nil, false, [], {}, {'eligible_statuses'=>[]}, {'eligible_statuses'=>['active'],'contact_mode'=>'guess'},
   {'eligible_statuses'=>['active'],'contact_mode'=>'registered_contact','target_percent'=>Float::NAN},
   {'eligible_statuses'=>['active'],'contact_mode'=>'registered_contact','target_percent'=>101},
   {'eligible_statuses'=>['active'],'contact_mode'=>'registered_contact','unknown'=>1},
   {'eligible_statuses'=>['active','active'],'contact_mode'=>'registered_contact'}].each_with_index do |v,i|
    define_method("test_invalid_policy_#{i}") { assert_raises(ArgumentError) { P.normalize!(v) } }
  end
end

class ApprovedLocalRoleTest < Minitest::Test
  R = JrcRelationship::LocalRoleRules
  def config(role='analyst',grants:[],categories:[])
    { 'enabled'=>true, 'roles'=>JSON.parse(JSON.generate(R::DEFAULTS)),
      'members'=>[{'user_id'=>8,'role'=>role,'grants'=>grants,'document_categories'=>categories}] }
  end
  def allow(rule, action, **opts)
    R.allowed?(rule,user_id:8,action:action,owner_id:8,**opts)
  end
  def test_absent_config_preserves_native_authority_not_a_grant
    assert R.allowed?(nil,user_id:8,action:'work')
  end
  def test_disabled_config_preserves_native_authority
    assert allow(config.merge('enabled'=>false),'configure')
  end
  def test_unmapped_user_denied_in_configured_scope
    refute R.allowed?(config,user_id:7,action:'view',owner_id:7)
  end
  def test_viewer_only_reads
    rule=config('viewer');assert allow(rule,'view');%w[work configure request_transfer approve_transfer execute_transfer export_data].each{|a|refute allow(rule,a)}
  end
  def test_analyst_operates_own_client_only
    rule=config;assert allow(rule,'work');refute R.allowed?(rule,user_id:8,action:'work',owner_id:7)
  end
  def test_analyst_can_request_not_execute
    assert allow(config,'request_transfer');refute allow(config,'execute_transfer');refute allow(config,'manage_eligibility')
  end
  def test_supervisor_can_request_eligibility_not_execute_it
    assert allow(config('supervisor'),'request_eligibility');refute allow(config('supervisor'),'manage_eligibility')
  end
  def test_supervisor_team_scope_does_not_include_foreign_team
    rule=config('supervisor')
    assert R.allowed?(rule,user_id:8,action:'work',owner_id:7,team_id:3,actor_team_ids:[3])
    refute R.allowed?(rule,user_id:8,action:'work',owner_id:7,team_id:4,actor_team_ids:[3])
  end
  def test_manager_needs_export_grant_even_with_action
    refute allow(config('manager'),'export_data')
    assert allow(config('manager',grants:['export_data']),'export_data')
    refute allow(config('manager',grants:['export_data']),'export_history')
  end
  def test_document_view_is_not_download
    rule=config('analyst',grants:['document_view'],categories:['registration'])
    assert allow(rule,'document_view',document_category:'registration')
    refute allow(rule,'document_download',document_category:'registration')
  end
  def test_document_category_is_explicit
    rule=config('manager',grants:['document_view'],categories:['registration'])
    refute allow(rule,'document_view',document_category:'contract')
  end
  def test_grant_cannot_expand_role_actions
    rule=config('viewer',grants:['export_data']);refute allow(rule,'export_data')
  end
  def test_metadata_sentinel_does_not_fabricate_source_visibility
    assert R.allowed?(config,user_id:8,action:'work',owner_id: :metadata)
    refute R.allowed?(config,user_id:8,action:'work',owner_id:nil)
  end
  def test_local_rules_do_not_modify_user_or_inputs
    rule=config;before=JSON.generate(rule);allow(rule,'view');assert_equal before,JSON.generate(rule)
  end
  def test_unauthorized_action_name_refused
    refute allow(config('manager'),'delete_everything')
  end
  def test_unknown_grant_rejected
    rule=config;rule['members'][0]['grants']=['configure'];assert_raises(ArgumentError){R.normalize!(rule)}
  end
  def test_duplicate_member_rejected
    rule=config;rule['members'] << rule['members'].first.dup;assert_raises(ArgumentError){R.normalize!(rule)}
  end
  def test_arbitrary_role_rejected
    rule=config;rule['members'][0]['role']='root';assert_raises(ArgumentError){R.normalize!(rule)}
  end
  def test_duplicate_role_action_rejected
    rule=config;rule['roles']['viewer']['actions']=['view','view'];assert_raises(ArgumentError){R.normalize!(rule)}
  end
  def test_profile_changes_respect_the_approved_read_only_boundary
    rule = config('viewer')
    rule['roles']['viewer']['actions'] << 'work'
    assert_raises(ArgumentError) { R.normalize!(rule) }
  end
  def test_enabling_requires_explicit_boolean
    assert_raises(ArgumentError){R.normalize!(config.merge('enabled'=>'true'))}
  end
  def test_ids_are_exact_positive_integers
    [false,[],{},0,-1,'8',1.1].each do |v|
      rule=config;rule['members'][0]['user_id']=v;assert_raises(ArgumentError){R.normalize!(rule)}
    end
  end
end

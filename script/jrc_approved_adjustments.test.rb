require 'minitest/autorun'
require 'date'
module JrcApprovals
  class Error < StandardError; end
end
require_relative '../app/services/jrc_approvals/adjustment_policy'
require_relative '../app/services/jrc_approvals/review_directive_policy'
class ApprovedAdjustmentPolicyTest < Minitest::Test
  P=JrcApprovals::AdjustmentPolicy
  D=JrcApprovals::ReviewDirectivePolicy
  def config(fields);{'schema_version'=>1,'fields'=>fields};end
  def authorize(key,fields,changes,today:Date.new(2026,11,9))
    P.authorize!({'adjustments'=>config(fields)},key,changes,today:today)
  end
  def test_no_hardcoded_commercial_bands
    [0,3,5,10,10000].each{|n|assert authorize('crm.order_price',{'discount_cents'=>{'min'=>0,'max'=>10000}},{'discount_cents'=>n})}
  end
  def test_legacy_discount_adapter_preserved
    assert P.authorize!({},'crm.proposal_send',{'discount_cents'=>1200})
  end
  def test_financial_requires_explicit_config
    assert_raises(JrcApprovals::Error){P.authorize!({},'crm.order_terms',{'installments_count'=>2})}
  end
  def test_terms_cannot_hide_price_or_product_edits
    %w[discount_cents product_id total_cents owner_id signature_status].each{|field|assert_raises(JrcApprovals::Error){authorize('crm.order_terms',{'installments_count'=>{'min'=>1,'max'=>12}},{field=>1})}}
  end
  %w[crm.order_terms crm.proposal_terms].each do |key|
    define_method("test_#{key.tr('.','_')}_installment_boundaries"){
      [1,12].each{|n|assert authorize(key,{'installments_count'=>{'min'=>1,'max'=>12}},{'installments_count'=>n})}
      [0,13].each{|n|assert_raises(JrcApprovals::Error){authorize(key,{'installments_count'=>{'min'=>1,'max'=>12}},{'installments_count'=>n})}}
    }
  end
  [nil,false,true,[],{},'12',1.5,Float::INFINITY].each_with_index do |value,i|
    define_method("test_server_integer_type_#{i}"){assert_raises(JrcApprovals::Error){P.validate_changes!({'installments_count'=>value})}}
  end
  def test_options_are_exact_configuration
    assert authorize('crm.order_terms',{'payment_condition'=>{'options'=>%w[custom_term]}},{'payment_condition'=>'custom_term'})
    assert_raises(JrcApprovals::Error){authorize('crm.order_terms',{'payment_condition'=>{'options'=>%w[custom_term]}},{'payment_condition'=>'monthly'})}
  end
  def test_date_window_exact_closed_boundaries
    ['2026-11-09','2026-12-09'].each{|date|assert authorize('crm.order_terms',{'first_due_date'=>{'min_days'=>0,'max_days'=>30}},{'first_due_date'=>date})}
    ['2026-11-08','2026-12-10'].each{|date|assert_raises(JrcApprovals::Error){authorize('crm.order_terms',{'first_due_date'=>{'min_days'=>0,'max_days'=>30}},{'first_due_date'=>date})}}
  end
  ['2026-02-30','09/11/2026','2026-11-09T00:00:00Z',false,nil].each_with_index do |value,i|
    define_method("test_exact_date_#{i}"){assert_raises(JrcApprovals::Error){P.validate_changes!({'first_due_date'=>value})}}
  end
  def test_different_scopes_cannot_gain_unknown_fields
    assert_raises(JrcApprovals::Error){P.validate!(config({'first_billing_days'=>{'min'=>0,'max'=>30}}),'crm.order_terms')}
    assert_raises(JrcApprovals::Error){P.validate!(config({'first_due_date'=>{'min_days'=>0,'max_days'=>30}}),'crm.proposal_terms')}
  end
  def test_limits_require_typed_ranges
    [{'min'=>4,'max'=>3},{'min'=>0,'max'=>'12'},{'min'=>0,'max'=>12},{'min'=>1,'max'=>2147483648}].each{|rule|assert_raises(JrcApprovals::Error){P.validate!(config({'installments_count'=>rule}),'crm.order_terms')}}
  end
  def test_cannot_post_native_evidence
    assert_raises(JrcApprovals::Error){P.validate_changes!({'signature_evidence'=>true})}
  end
  def test_empty_policy_is_configuration_error
    assert_raises(JrcApprovals::Error){P.validate!(config({}),'crm.order_terms')}
  end
  def test_no_escalation_without_explicit_target
    assert_raises(JrcApprovals::Error){D.validate!({'actions'=>['escalate'],'escalation_policy_id'=>nil})}
  end
  def test_advice_is_separate_from_source_mutation
    %w[request_adjustment suggest_redaction].each{|k|assert_equal 'Human review',D.input!({'actions'=>[k],'escalation_policy_id'=>nil},k,' Human review ')}
  end
  def test_suggestion_requires_reason
    assert_raises(JrcApprovals::Error){D.input!({'actions'=>['suggest_redaction'],'escalation_policy_id'=>nil},'suggest_redaction',' ')}
  end
  def test_directive_not_allowed_is_denied
    assert_raises(JrcApprovals::Error){D.input!({'actions'=>['request_adjustment'],'escalation_policy_id'=>nil},'escalate','Please escalate')}
  end
  def test_arbitrary_actions_and_fields_are_refused
    assert_raises(JrcApprovals::Error){D.validate!({'actions'=>['update_sql'],'escalation_policy_id'=>nil})}
    assert_raises(JrcApprovals::Error){D.validate!({'actions'=>['escalate'],'escalation_policy_id'=>1,'model'=>'User'})}
  end
  def test_reference_policy_uses_integer_identity
    assert D.validate!({'actions'=>['escalate'],'escalation_policy_id'=>2})
    [-1,0,'2',false].each{|id|assert_raises(JrcApprovals::Error){D.validate!({'actions'=>['escalate'],'escalation_policy_id'=>id})}}
  end
end

# Exercise the real gate branch without Rails persistence; other calls are stubs.
module JrcApprovals
  class GratuityCatalog
    def self.gratuity_key?(_key); false; end
  end
  class FinancialCatalog
    EVENTS = { 'crm.proposal_terms' => 'Proposal', 'crm.order_terms' => 'SalesOrder' }.freeze
  end
end
require_relative '../app/services/jrc_approvals/commercial_gate'
class ApprovedFinancialContextGateTest < Minitest::Test
  def gate
    g = JrcApprovals::CommercialGate.new(account: nil, user: nil)
    g.define_singleton_method(:payload) { |status, snapshot, required: true| {status: status, required: required, snapshot: snapshot} }
    g
  end
  %w[crm.proposal_terms crm.order_terms].each do |key|
    define_method("test_#{key.tr('.', '_')}_needs_own_policy_despite_no_price_exception") do
      value = gate.send(:context_result, key, {'values'=>{'price_status'=>'evaluated','below_minimum_count'=>0}})
      assert_nil value
    end
    define_method("test_#{key.tr('.', '_')}_pending_price_context_is_blocked") do
      value = gate.send(:context_result, key, {'values'=>{'price_status'=>'pending','below_minimum_count'=>0}})
      assert_equal 'PRICE_CONTEXT_PENDING', value[:status]
      assert_equal true, value[:required]
    end
  end
  def test_legacy_price_no_exception_path_is_unchanged
    value = gate.send(:context_result, 'crm.order_price', {'values'=>{'price_status'=>'evaluated','below_minimum_count'=>0}})
    assert_equal 'ready', value[:status]
    assert_equal false, value[:required]
  end
  def test_contract_signature_keeps_its_native_evidence_path
    assert_nil gate.send(:context_result, 'contracts.company_signature', {'values'=>{}})
  end
end

require 'ostruct'
require_relative '../app/services/jrc_approvals/draft_review_catalog'
class ApprovedDraftReviewStateTest < Minitest::Test
  %w[sent signed].each do |state|
    define_method("test_#{state}_draft_cannot_be_review_mutated") do
      refute JrcApprovals::DraftReviewCatalog.mutable?(OpenStruct.new(signature_status: state, status: 'draft'))
    end
  end
  %w[active completed canceled terminated].each do |state|
    define_method("test_#{state}_contract_cannot_enter_draft_review") do
      refute JrcApprovals::DraftReviewCatalog.mutable?(OpenStruct.new(signature_status: 'pending', status: state))
    end
  end
  def test_unsigned_draft_passes_state_check_only
    assert JrcApprovals::DraftReviewCatalog.mutable?(OpenStruct.new(signature_status: 'pending', status: 'draft'))
  end
end

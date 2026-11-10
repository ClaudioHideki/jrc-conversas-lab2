require 'minitest/autorun'
require 'minitest/mock'
require 'ostruct'

# Only mutation orchestration is tested here. Financial calculation, native
# authorization and DB rollback are dependencies; this is NOT a PostgreSQL test.
module JrcApprovals
  class Error < StandardError; end
  class TierRanges
    MAX_EXACT_BOUND = 9_007_199_254_740_991
  end
  class CommercialInvalidation
    class << self; attr_accessor :calls; end
    def self.call(**args); self.calls << args; end
  end
end
module JrcCrm
  class OrderFinancials
    class << self; attr_accessor :calls, :output; end
    def initialize(**args); self.class.calls << args; end
    def call; self.class.output; end
    def self.attributes_for(result); result.slice(:discount_cents, :total_cents); end
    def self.snapshot_for(result, old); old.merge('financials' => result); end
  end
  class AuditEvent
    class << self; attr_accessor :events; end
    def self.create!(**attrs); self.events << attrs; end
  end
end
class Hash
  def deep_dup; Marshal.load(Marshal.dump(self)); end
end
require_relative '../../app/services/jrc_approvals/adjustment_sources'
require_relative '../../app/services/jrc_crm/order_discount_mutation'

class OrderDiscountMutationTest < Minitest::Test
  Service = JrcCrm::OrderDiscountMutation
  Items = Class.new(Array) { def order(*); self; end }
  class Order
    attr_accessor :snapshot, :status, :terms_locked, :invoice_exists, :saves, :locks
    attr_reader :id, :account
    def initialize
      @id=50;@account=Object.new;@status='draft';@terms_locked=false;@invoice_exists=false;@saves=0;@locks=0
      @values={'discount_cents'=>300,'total_cents'=>700,'monthly_cents'=>0,'owner_id'=>1,'contact_id'=>2}
      @snapshot={'discount_percent'=>'30','unrelated'=>'preserved'}
    end
    def attributes; @values.dup; end
    def invoices; OpenStruct.new(exists?: @invoice_exists); end
    def commercial_terms_locked?; @terms_locked; end
    def order_items; Items.new([OpenStruct.new(attributes:{'quantity'=>1,'unit_price_cents'=>1000})]); end
    def with_lock; @locks+=1; yield; end
    def assign_attributes(values); values.each { |k,v| @values[k.to_s]=v }; end
    def save!; @saves+=1; end
    def reload; self; end
  end
  def setup
    @order=Order.new;@actor=OpenStruct.new(id:7);@auth=[]
    JrcCrm::OrderFinancials.calls=[];JrcCrm::OrderFinancials.output={discount_cents:100,total_cents:900}
    JrcCrm::AuditEvent.events=[];JrcApprovals::CommercialInvalidation.calls=[]
  end
  def execute(changes={'discount_cents'=>100})
    Service.stub(:authorize!, ->(source,actor){@auth<<[source,actor]}) { Service.call!(order:@order,actor:@actor,attributes:changes) }
  end
  def test_uses_native_financial_projection_and_two_authorization_checks
    assert_same @order, execute
    assert_equal 2,@auth.length
    assert_equal 1,@order.locks
    assert_equal 1,@order.saves
  end
  def test_removes_old_percent_only_in_calculator_snapshot
    execute
    assert_nil JrcCrm::OrderFinancials.calls.first[:attributes]['snapshot']['discount_percent']
    assert_equal 'preserved', @order.snapshot['unrelated']
  end
  def test_preserves_owner_customer_status_and_native_items
    before=@order.attributes.slice('owner_id','contact_id');execute
    assert_equal before,@order.attributes.slice(*before.keys)
    assert_equal 'draft',@order.status
    assert_equal 1,JrcCrm::OrderFinancials.calls.first[:items].size
  end
  def test_records_actual_actor_and_original_values
    execute
    audit=JrcCrm::AuditEvent.events.fetch(0)
    assert_equal 7,audit[:actor_id]
    assert_equal 300,audit[:from_value]['discount_cents']
    assert_equal 100,audit[:to_value]['discount_cents']
  end
  def test_invalidates_native_approvals_after_save
    execute
    assert_equal 1,JrcApprovals::CommercialInvalidation.calls.size
    assert_same @actor,JrcApprovals::CommercialInvalidation.calls.first[:user]
  end
  def test_capped_discount_is_rejected_before_mutation
    JrcCrm::OrderFinancials.output={discount_cents:90,total_cents:910}
    assert_raises(JrcApprovals::Error) { execute }
    assert_equal 0,@order.saves
    assert_empty JrcCrm::AuditEvent.events
  end
  def test_contractual_lock_cannot_be_overridden
    @order.terms_locked=true
    assert_raises(JrcApprovals::Error) { execute }
    assert_empty JrcCrm::OrderFinancials.calls
  end
  def test_any_invoice_blocks_discount_adjustment
    @order.invoice_exists=true
    assert_raises(JrcApprovals::Error) { execute }
    assert_equal 0,@order.saves
  end
  def test_operational_status_is_not_changed_or_accepted
    @order.status='approved'
    assert_raises(JrcApprovals::Error) { execute }
    assert_equal 'approved',@order.status
  end
  def test_pending_uncommitted_order_keeps_native_state
    @order.status='pending';execute
    assert_equal 'pending',@order.status
  end
  def test_unallowed_field_is_rejected_before_lock_and_write
    assert_raises(JrcApprovals::Error) { execute({'discount_cents'=>100,'owner_id'=>99}) }
    assert_equal 0,@order.locks
  end
  def test_authorization_is_required_before_calculation
    Service.stub(:authorize!, ->(*){raise SecurityError,'denied'}) do
      assert_raises(SecurityError) { Service.call!(order:@order,actor:@actor,attributes:{'discount_cents'=>100}) }
    end
    assert_empty JrcCrm::OrderFinancials.calls
    assert_equal 0,@order.saves
  end
end

# Runs the real capture service against bounded storage doubles, not PostgreSQL.
require 'minitest/autorun'
require 'ostruct'
module ActiveRecord; class RecordNotFound < StandardError; end; end
class Time
  def self.current = now
end
module JrcRelationship
  class PortfolioGroups
    FIELDS = %w[name objective owner_id team_id business_unit_id segment_id visibility status goals].freeze
  end
  class PortfolioGroupConfiguration
    RULES = %w[portfolio_capacity_limits portfolio_transfer_approval_required portfolio_review_validity_minutes portfolio_local_access].freeze
  end
  class TestRows
    def initialize(rows) = @rows = rows
    def where(**attributes) = self.class.new(@rows.select { |row| attributes.all? { |key,value| Array(value).include?(row[key.to_s]) } })
    def order(*) = self
    def pluck(*keys)
      @rows.map { |row| keys.length == 1 ? row[keys.first.to_s] : keys.map { |key| row[key.to_s] } }
    end
    def find_by(**attributes)
      row = @rows.find { |item| attributes.all? { |key,value| value == item[key.to_s] } }
      row && OpenStruct.new(row)
    end
  end
  class PortfolioGroup
    attr_accessor :attributes, :customer_links
    class << self; attr_accessor :record; end
    def self.find_by!(account_id:,id:)
      raise ActiveRecord::RecordNotFound unless record.account_id==account_id && record.id.to_s==id.to_s
      record
    end
    def initialize(attributes,links)
      @attributes=attributes;@customer_links=TestRows.new(links)
    end
    def id = attributes.fetch('id')
    def account_id = attributes.fetch('account_id')
  end
  class Assignment
    class << self;attr_accessor :rows;end
    def self.where(**attributes) = TestRows.new(rows).where(**attributes)
  end
  class Configuration
    attr_accessor :versions
    def initialize(account_id,scope_key,versions)
      @account_id,@scope_key,@versions=account_id,scope_key,TestRows.new(versions)
    end
    attr_reader :account_id,:scope_key
  end
  class PortfolioHistoryReceipt
    class << self;attr_accessor :captured;end
    def self.create!(**attributes)
      raise ArgumentError,'invalid proof' unless PortfolioHistoryBoundary.valid?(attributes.fetch(:snapshot))
      self.captured=attributes
    end
  end
end
require_relative '../app/services/jrc_relationship/portfolio_history_boundary'
require_relative '../app/services/jrc_relationship/portfolio_history_details'

class PortfolioHistoryCaptureTest < Minitest::Test
  def setup
    @group=JrcRelationship::PortfolioGroup.new({'id'=>3,'account_id'=>1,'name'=>'Synthetic group','owner_id'=>8,'team_id'=>2,'business_unit_id'=>4,'segment_id'=>5,'visibility'=>'private'},[{'assignment_id'=>7,'active'=>true}])
    JrcRelationship::PortfolioGroup.record=@group
    JrcRelationship::Assignment.rows=[{'account_id'=>1,'id'=>7,'company_id'=>19,'contact_id'=>nil,'business_unit_id'=>4},{'account_id'=>1,'id'=>9,'company_id'=>22,'contact_id'=>nil,'business_unit_id'=>4}]
    JrcRelationship::PortfolioHistoryReceipt.captured=nil
    @event=OpenStruct.new(id:11,account_id:1,actor_type:'User',actor_id:8,resource_type:'JrcRelationship::PortfolioGroup',resource_id:3,from_value:{'objective'=>'old'},to_value:{'objective'=>'new','reason'=>'Reviewed'},metadata:{'action'=>'portfolio_group_updated'})
  end
  def capture(resource=@group)
    JrcRelationship::PortfolioHistoryDetails.capture!(@event,resource:resource)
    JrcRelationship::PortfolioHistoryReceipt.captured&.fetch(:snapshot)
  end
  def test_capture_uses_actual_event_identity_and_original_values
    row=capture;assert_equal({'objective'=>'old'},row['before']);assert_equal 'Reviewed',row['reason']
    assert_equal JrcRelationship::PortfolioHistoryDetails.event_digest(@event),row['event_digest']
  end
  def test_snapshot_hash_matches_capture
    row=capture;assert_equal JrcRelationship::PortfolioHistoryBoundary.digest(row),JrcRelationship::PortfolioHistoryReceipt.captured[:digest]
  end
  def test_before_private_owner_is_not_replaced_by_current_owner
    @event.from_value={'owner_id'=>7};row=capture
    assert_equal [7,8],row['boundaries'].map{|r|r['owner_id']}
  end
  def test_removed_customers_are_in_historic_authorization_set
    @event.metadata={'action'=>'portfolio_group_customers_updated'};@event.from_value={'customers'=>[[9,true]]};@event.to_value={'customers'=>[[9,false]],'reason'=>'Removed'}
    assert_equal [7,9],capture['origins'].map{|r|r['id']}
  end
  def test_unresolved_assignment_cannot_be_silently_omitted
    @event.from_value={'customers'=>[[99,true]]};assert_raises(ActiveRecord::RecordNotFound){capture}
  end
  def test_cross_tenant_assignment_cannot_be_captured
    JrcRelationship::Assignment.rows[0]['account_id']=2
    assert_raises(ActiveRecord::RecordNotFound){capture}
  end
  def test_unrelated_actions_do_not_create_receipts
    @event.metadata={'action'=>'action_created'};assert_nil capture
  end
  def test_export_of_old_events_does_not_backfill_receipts
    @event.metadata={'action'=>'portfolio_group_history_exported'};assert_nil capture
  end
  def test_unknown_raw_fields_are_not_captured
    @event.to_value['api_token']='synthetic-not-a-token';refute capture['after'].key?('api_token')
  end
  def test_customer_names_are_not_stored_in_origin_proof
    JrcRelationship::Assignment.rows[0]['name']='Sensitive synthetic name'
    refute capture['origins'][0].key?('name')
  end
  def test_rule_scope_is_read_from_native_portfolio_key
    @event.resource_type='JrcRelationship::Configuration';@event.resource_id=17;@event.metadata={'action'=>'configuration_versioned'}
    @event.from_value={'version'=>1,'rules'=>{'portfolio_review_validity_minutes'=>20,'health_private'=>'ignored'}}
    @event.to_value={'version'=>2,'rules'=>{'portfolio_review_validity_minutes'=>30}}
    row=capture(JrcRelationship::Configuration.new(1,'portfolio:3',[]));assert_equal 'rules',row['kind'];refute row['before']['rules'].key?('health_private')
  end
  def test_native_local_access_is_retained_in_event_but_excluded_from_history_projection
    @event.metadata={'action'=>'configuration_versioned'}
    @event.from_value={'version'=>1,'rules'=>{'portfolio_local_access'=>{'enabled'=>false},'portfolio_review_validity_minutes'=>20}}
    @event.to_value={'version'=>2,'rules'=>{'portfolio_local_access'=>{'enabled'=>true},'portfolio_review_validity_minutes'=>30}}
    row=capture(JrcRelationship::Configuration.new(1,'portfolio:3',[]))
    assert_equal 30,row['after']['rules']['portfolio_review_validity_minutes']
    refute row['before']['rules'].key?('portfolio_local_access')
    refute row['after']['rules'].key?('portfolio_local_access')
    assert_equal true,@event.to_value['rules']['portfolio_local_access']['enabled']
  end
  def test_restore_uses_exact_version_record_not_current_rules
    @event.metadata={'action'=>'configuration_restored'};@event.from_value={'version'=>1};@event.to_value={'version'=>2,'reason'=>'Restored'}
    cfg=JrcRelationship::Configuration.new(1,'portfolio:3',[{'account_id'=>1,'version'=>1,'rules'=>{'portfolio_review_validity_minutes'=>20}},{'account_id'=>1,'version'=>2,'rules'=>{'portfolio_review_validity_minutes'=>40}}])
    row=capture(cfg);assert_equal 20,row['before']['rules']['portfolio_review_validity_minutes'];assert_equal 40,row['after']['rules']['portfolio_review_validity_minutes']
  end
  def test_non_portfolio_configuration_does_not_create_history
    @event.metadata={'action'=>'configuration_versioned'}
    assert_nil capture(JrcRelationship::Configuration.new(1,'account',[]))
  end
end

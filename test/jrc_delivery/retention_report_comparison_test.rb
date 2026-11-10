require 'minitest/autorun'
require 'ostruct'
require 'date'
require 'time'

# Runs the real report orchestration and metric. Database/configuration/time-zone
# lookups are explicit boundary doubles. This is NOT Rails or PostgreSQL QA.
module Pundit; class NotAuthorizedError < StandardError; end; end
module JrcRelationship; end
class NilClass; def present? = false; end
class String; def present? = !empty?; end
class Time
  class << self
    attr_accessor :fixture_now
    def current = fixture_now
    def find_zone!(_name) = Object.new.tap { |zone| def zone.local(y,m,d) = Time.utc(y,m,d) }
  end
end
class JrcRelationship::RetentionState
  def self.transaction(isolation:)
    raise 'Unexpected isolation' unless isolation == :repeatable_read
    yield
  end
end
class JrcRelationship::RetentionCoverage
  class << self
    attr_accessor :coverage
    def find_by(account_id:)
      raise 'Foreign account' unless account_id == 1
      coverage
    end
  end
end
class JrcRelationship::Context
  class << self
    attr_accessor :fixture, :build_count, :change_on
    def new(member)
      raise 'A stale/wrong context replaced the native membership' unless member.equal?(fixture.member)
      self.build_count += 1
      value = fixture.dup
      value.access_signature = (change_on && build_count >= change_on) ? 'revoked' : 'v1'
      value
    end
  end
end
require_relative '../../app/services/jrc_relationship/retention_policy'
require_relative '../../app/services/jrc_relationship/retention_metric'
require_relative '../../app/services/jrc_relationship/retention_report'

class BoundaryRetentionReport < JrcRelationship::RetentionReport
  class << self
    attr_accessor :snapshots, :allowed
  end
  private
  def states(_context, boundary, inclusive:)
    self.class.snapshots.fetch([boundary.to_date.iso8601, inclusive], [])
  end
  def cohort_authorized?(_context, _cohort) = self.class.allowed
end

class RetentionReportComparisonTest < Minitest::Test
  def setup
    member = Struct.new(:account_id, :user_id).new(1, 8) # intentionally no #member
    user = OpenStruct.new(id: 8)
    def user.reload = self
    def user.active_for_authentication? = true
    @context = OpenStruct.new(member: member, account: OpenStruct.new(id: 1), user: user,
      policy: OpenStruct.new(admin?: true), formatting: {timeZone: 'UTC'}, access_signature: 'v1',
      configuration: OpenStruct.new(version: 1, effective_rules: {'retention_policy' => {
        'eligible_statuses' => ['active'], 'contact_mode' => 'relationship_status', 'target_percent' => nil}}))
    JrcRelationship::Context.fixture = @context
    JrcRelationship::Context.build_count = 0
    JrcRelationship::Context.change_on = nil
    JrcRelationship::RetentionCoverage.coverage = OpenStruct.new(started_at: Time.utc(2026, 9, 1))
    Time.fixture_now = Time.utc(2026, 11, 10)
    BoundaryRetentionReport.snapshots = {}
    BoundaryRetentionReport.allowed = true
  end

  def row(id, status = 'active')
    {'customer_key' => "company:#{id}", 'customer_type' => 'company', 'assignment_id' => id,
     'owner_id' => 8, 'source_present' => true, 'master_active' => true, 'status' => status}
  end

  def current_cohort
    BoundaryRetentionReport.snapshots[['2026-10-01', true]] = (1..100).map { |id| row(id) }
    BoundaryRetentionReport.snapshots[['2026-10-02', false]] = (1..110).map { |id| row(id, (93..100).include?(id) ? 'inactive' : 'active') }
  end

  def run_report(**options)
    BoundaryRetentionReport.new(@context).call(period: 'custom', from: '2026-10-01', to: '2026-10-01', **options)
  end

  def test_default_comparison_does_not_pass_account_user_to_context_constructor
    current_cohort
    result = run_report
    assert_equal 92.0, result[:value]
    assert_equal 100, result[:initial]
    assert result.key?(:previous)
    refute result[:previous][:available]
  end

  def test_no_history_with_default_comparison_is_unavailable_not_a_server_error
    JrcRelationship::RetentionCoverage.coverage = nil
    result = run_report
    refute result[:available]
    assert_nil result[:value]
    assert_equal 'insufficient_history', result[:previous][:code]
  end

  def test_available_previous_period_has_its_own_cohort
    current_cohort
    BoundaryRetentionReport.snapshots[['2026-09-30', true]] = (1..100).map { |id| row(id) }
    BoundaryRetentionReport.snapshots[['2026-10-01', false]] = (1..100).map { |id| row(id, id > 90 ? 'inactive' : 'active') }
    result = run_report
    assert_equal 90.0, result[:previous][:value]
    assert_equal 2.0, result[:change_percentage_points]
    assert_equal '2026-09-30', result[:previous][:from]
  end

  def test_comparison_can_be_disabled_without_changing_current_metric
    current_cohort
    result = run_report(compare: false)
    assert_equal 92.0, result[:value]
    refute result.key?(:previous)
  end

  def test_zero_denominator_is_unavailable_for_both_periods
    result = run_report
    assert_equal 'not_applicable', result[:code]
    assert_nil result[:value]
    assert_nil result[:previous][:value]
  end

  def test_valid_zero_retention_is_not_replaced_by_missing_data
    BoundaryRetentionReport.snapshots[['2026-10-01', true]] = [row(1)]
    BoundaryRetentionReport.snapshots[['2026-10-02', false]] = [row(1, 'inactive')]
    result = run_report
    assert_equal 0.0, result[:value]
    assert_equal 1, result[:exits]
  end

  def test_final_scope_recheck_still_blocks_a_change_during_comparison
    current_cohort
    JrcRelationship::Context.change_on = 5
    assert_raises(Pundit::NotAuthorizedError) { run_report }
  end

  def test_unavailable_native_cohort_does_not_shrink_denominator
    current_cohort
    BoundaryRetentionReport.allowed = false
    result = run_report
    refute result[:available]
    assert_equal 'scope_unavailable', result[:code]
    assert_nil result[:initial]
  end

  def test_unclosed_period_does_not_construct_a_previous_report
    Time.fixture_now = Time.utc(2026, 10, 1, 12)
    result = run_report
    assert_equal 'period_not_closed', result[:code]
    refute result.key?(:previous)
  end
end

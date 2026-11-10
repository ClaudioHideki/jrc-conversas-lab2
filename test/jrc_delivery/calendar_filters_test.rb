require 'minitest/autorun'
require 'time'
module JrcCrm; end
module ActiveRecord
  class Base
    def self.sanitize_sql_like(value) = value.gsub(/[\\%_]/) { |x| "\\#{x}" }
  end
end
require_relative '../../app/services/jrc_crm/calendar_page'
require_relative '../../app/services/jrc_crm/calendar_filters'

# Captures relation operations, not a substitute for PostgreSQL integration.
class CalendarFiltersTest < Minitest::Test
  class Scope
    attr_reader :calls
    def initialize = @calls = []
    def where(*args)
      return self if args.empty?
      @calls << [:where, args]; self
    end
    def not(**args) = (@calls << [:not, args]; self)
    def left_joins(*args) = (@calls << [:left_joins, args]; self)
  end
  def setup
    @scope=Scope.new
    @now=Time.utc(2026,11,9,12)
  end
  def apply(params = {}) = JrcCrm::CalendarFilters.new(scope: @scope, params: params, now: @now).call
  def test_no_filters_preserve_authorized_scope
    assert_same @scope,apply
    assert_empty @scope.calls
  end
  def test_type_is_applied_before_returning_relation
    apply(activity_type:'call')
    assert_includes @scope.calls,[:where,[{activity_type:'call'}]]
  end
  def test_open_excludes_completed_and_cancelled
    apply(status:'open')
    assert_includes @scope.calls,[:where,[{completed_at:nil}]]
    assert_includes @scope.calls,[:not,{status:%w[completed cancelled]}]
  end
  def test_overdue_uses_the_supplied_current_time
    apply(status:'overdue')
    assert_includes @scope.calls,[:where,['jrc_crm_activities.due_at < ?',@now]]
  end
  def test_completed_accepts_native_status_or_timestamp
    apply(status:'completed')
    assert_includes @scope.calls,[:where,["jrc_crm_activities.completed_at IS NOT NULL OR jrc_crm_activities.status = ?",'completed']]
  end
  def test_search_is_bound_and_wildcards_escaped
    apply(search:"a%_'; DROP TABLE users; --")
    assert_includes @scope.calls,[:left_joins,[:deal,:lead,:contact,:company]]
    sql,args=@scope.calls.last[1]
    refute_includes sql,'DROP TABLE'
    assert_includes args[:query],'a\\%\\_'
    assert_equal 6,sql.scan('ILIKE :query').length
  end
  def test_blank_search_does_not_join
    apply(search:'   ')
    assert_empty @scope.calls
  end
  [false,true,[],{},'bad',0].each_with_index do |value,i|
    define_method("test_invalid_type_#{i}"){assert_raises(JrcCrm::CalendarPage::InvalidQuery){apply(activity_type:value)}}
    define_method("test_invalid_status_#{i}"){assert_raises(JrcCrm::CalendarPage::InvalidQuery){apply(status:value)}}
  end
  [false,[],{},'a'*257,"a\0b"].each_with_index do |value,i|
    define_method("test_invalid_search_#{i}"){assert_raises(JrcCrm::CalendarPage::InvalidQuery){apply(search:value)}}
  end
end

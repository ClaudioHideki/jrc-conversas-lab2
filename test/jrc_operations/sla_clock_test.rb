# Standalone unit tests: persistence and the calendar are doubles; no Rails boot or database.
require 'minitest/autorun'
require 'minitest/mock'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/object/inclusion'
require 'active_support/core_ext/hash/except'
require 'time'
class << Time
  alias_method :current, :now unless method_defined?(:current)
end
module JrcOperations; end
require_relative '../../app/services/jrc_operations/business_time'
require_relative '../../app/services/jrc_operations/sla_clock'

class OperationsSlaClockTest < Minitest::Test
  Request = Struct.new(:id, :account_id, :operations_sla_policy, :sla_started_at, :first_action_due_at, :first_action_at,
                       :stage_due_at, :sla_due_at, :due_at, :sla_paused_at, :sla_paused_seconds, :updated_at,
                       :activity, :status, :completed_at, keyword_init: true) do
    def assign_attributes(fields)
      fields.each { |key, value| self[key] = value }
    end
    alias update_columns assign_attributes
  end
  Activity = Struct.new(:due_at, :metadata, keyword_init: true) do
    def update!(fields)
      fields.each { |key, value| self[key] = value }
    end
  end
  Policy = Struct.new(:first_action_minutes, :stage_minutes, :total_minutes, :business_hours, :alert_thresholds, :pause_statuses, keyword_init: true) do
    def pause_status?(status)
      Array(pause_statuses || ['waiting_customer']).include?(status)
    end
  end

  def setup
    @start = Time.utc(2026, 10, 5, 8)
    @policy = Policy.new(first_action_minutes: 60, total_minutes: 120, business_hours: {}, alert_thresholds: [50, 75, 90, 100])
    @activity = Activity.new(due_at: @start + 7200, metadata: { 'source' => 'relationship' })
    @request = Request.new(id: 1, account_id: 7, operations_sla_policy: @policy, sla_started_at: @start,
                           first_action_due_at: @start + 3600, sla_due_at: @start + 7200,
                           due_at: @start + 7200, sla_paused_seconds: 0, activity: @activity, status: 'open')
    @clock = JrcOperations::SlaClock.new(@request)
    @calendar = Object.new
    def @calendar.seconds_between(first, last)
      [last - first, 0].max
    end
    def @calendar.add_minutes(time, minutes)
      minutes && time + minutes * 60
    end
  end

  def test_pause_freezes_the_clock_and_marks_the_existing_agenda_projection
    Time.stub(:current, @start + 1800) do
      @clock.stub(:audit_clock_event!, nil) { @clock.status_changed!(from: 'open', to: 'waiting_customer') }
    end
    assert_equal @start + 1800, @request.sla_paused_at
    assert_equal @request.due_at, @activity.due_at
    assert_equal @request.sla_paused_at.iso8601, @activity.metadata['relationship_sla_paused_at']
    assert_equal 'relationship', @activity.metadata['source']
    Time.stub(:current, @start + 10_800) do
      JrcOperations::BusinessTime.stub(:new, @calendar) do
        assert_equal 25.0, @clock.snapshot[:percent_elapsed]
        assert_empty @clock.snapshot[:triggered_thresholds]
      end
    end
  end

  def test_resume_moves_all_deadlines_and_the_existing_agenda_by_the_same_pause
    @request.sla_paused_at = @start + 1800
    @activity.metadata['relationship_sla_paused_at'] = @request.sla_paused_at.iso8601
    Time.stub(:current, @start + 9000) do
      JrcOperations::BusinessTime.stub(:new, @calendar) do
        @clock.stub(:audit_clock_event!, nil) { @clock.status_changed!(from: 'waiting_customer', to: 'in_progress') }
      end
    end
    assert_equal @start + 10_800, @request.first_action_due_at
    assert_equal @start + 14_400, @request.sla_due_at
    assert_equal @request.sla_due_at, @request.due_at
    assert_equal @request.due_at, @activity.due_at
    assert_nil @request.sla_paused_at
    refute @activity.metadata.key?('relationship_sla_paused_at')
    assert_equal 7200, @request.sla_paused_seconds
  end

  def test_resume_preserves_an_already_overdue_deadline_and_an_explicit_action_deadline
    @request.sla_paused_at = @start + 5400
    @request.due_at = @start + 6000
    Time.stub(:current, @start + 9000) do
      JrcOperations::BusinessTime.stub(:new, @calendar) do
        @clock.stub(:audit_clock_event!, nil) { @clock.status_changed!(from: 'waiting_customer', to: 'open') }
        assert @clock.snapshot[:first_action_overdue]
      end
    end
    assert_equal @start + 7200, @request.first_action_due_at
    assert_equal @start + 9600, @request.due_at
    assert_equal @request.due_at, @activity.due_at
  end

  def test_first_action_is_recorded_once_and_completed_resolution_stops_alerts
    Time.stub(:current, @start + 1200) { @clock.mark_first_action! }
    Time.stub(:current, @start + 1800) { @clock.mark_first_action! }
    assert_equal @start + 1200, @request.first_action_at
    @request.status = 'completed'
    @request.completed_at = @start + 3600
    Time.stub(:current, @start + 86_400) do
      JrcOperations::BusinessTime.stub(:new, @calendar) do
        assert_equal 'stopped', @clock.snapshot[:state]
        assert_empty @clock.snapshot[:triggered_thresholds]
        refute @clock.snapshot[:total_overdue]
      end
    end
  end
  def test_finance_pause_and_switching_wait_reasons_keep_one_pause_until_resume
    @policy.pause_statuses = %w[waiting_customer waiting_finance]
    Time.stub(:current, @start + 1800) do
      @clock.stub(:audit_clock_event!, nil) { @clock.status_changed!(from: 'open', to: 'waiting_finance') }
    end
    Time.stub(:current, @start + 3600) do
      @clock.stub(:audit_clock_event!, nil) { @clock.status_changed!(from: 'waiting_finance', to: 'waiting_customer') }
    end
    assert_equal @start + 1800, @request.sla_paused_at
    assert_equal 0, @request.sla_paused_seconds
    assert_equal @request.sla_paused_at.iso8601, @activity.metadata['relationship_sla_paused_at']
    Time.stub(:current, @start + 9000) do
      JrcOperations::BusinessTime.stub(:new, @calendar) do
        @clock.stub(:audit_clock_event!, nil) { @clock.status_changed!(from: 'waiting_customer', to: 'in_progress') }
      end
    end
    assert_equal 7200, @request.sla_paused_seconds
    assert_equal @start + 10_800, @request.first_action_due_at
    assert_equal @start + 14_400, @request.sla_due_at
    assert_equal @request.due_at, @activity.due_at
    refute @activity.metadata.key?('relationship_sla_paused_at')
  end

  def test_finance_wait_respects_an_explicit_policy_without_pause
    @policy.pause_statuses = []
    Time.stub(:current, @start + 1800) do
      @clock.status_changed!(from: 'open', to: 'waiting_finance')
    end
    assert_nil @request.sla_paused_at
    assert_equal @start + 7200, @request.sla_due_at
    refute @activity.metadata.key?('relationship_sla_paused_at')
  end

end

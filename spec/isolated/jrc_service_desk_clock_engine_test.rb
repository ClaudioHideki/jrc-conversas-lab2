# frozen_string_literal: true
# Real LifecycleClocks engine with in-memory repository/zone doubles.
# NOT ActiveRecord, PostgreSQL, Pundit, native TZInfo or transaction testing.
require 'minitest/autorun'
require 'ostruct'
require 'time'
module JrcServiceDesk; end
%w[input canonical_json clock_escalation_policy lifecycle_rules lifecycle_dependency_error snapshot_calendar lifecycle_clocks].each do |name|
  require File.expand_path("../../app/services/jrc_service_desk/#{name}", __dir__)
end
module TZInfo
  class InvalidTimezoneIdentifier < StandardError; end
  class Timezone
    def self.get(name)
      raise InvalidTimezoneIdentifier unless name == 'Test/OffsetMinus3'
      new
    end
    def to_local(time); time.getlocal(-10800); end
    def local_to_utc(local, dst); raise unless dst.nil?; local + 10800; end
  end
end
class ClockFixture < OpenStruct
  def save!; true; end
  def update!(**values); values.each { |k,v| self[k] = v }; true; end
  def reload; self; end
  def met?; state == 'completed' && achieved_at ? achieved_at <= due_at : nil; end
end
class MemoryRows
  include Enumerable
  def initialize(&factory); @values=[]; @factory=factory; end
  def create!(**values)
    value = @factory ? @factory.call(values.merge(id: @values.size+1)) : ClockFixture.new(values.merge(id: @values.size+1))
    @values << value; value
  end
  def each(&block); @values.each(&block); end
  def exists?; @values.any?; end
  def order(*_arguments, **_keys); self; end
  # The engine uses descending number to get the current cycle.
  def first; @values.last; end
  def find_by(**filter); @values.find { |v| filter.all? { |k,x| v[k] == x } }; end
  def maximum(key); @values.map { |v| v[key] }.max; end
  def size; @values.size; end
end
class ClockEngineIsolatedTest < Minitest::Test
  def setup
    @start = Time.iso8601('2026-09-28T12:00:00Z')
    @snapshot = ClockFixture.new(id: 90, ticket_id: 1, account_id: 1, unit_id: 10, version: 1, timezone: 'Test/OffsetMinus3',
      policy_conditions: {'clock_budgets_seconds'=>{'first_response'=>7200,'resolution'=>28800}},
      calendar_conditions: {'format'=>'jrc-sd-snapshot-calendar-v1','weekly'=>(1..7).to_h { |n| [n.to_s,n<=5 ? [['09:00','17:00']] : []] },'holidays'=>[],'exceptions'=>{}})
    @cycles=MemoryRows.new do |values|
      ClockFixture.new(values.merge(sla_snapshot_id: values[:sla_snapshot].id, sla_clocks: MemoryRows.new))
    end
    @ticket=ClockFixture.new(id:1,account_id:1,unit_id:10,account:Object.new,unit:Object.new,opened_at:@start,latest_sla_snapshot:@snapshot,
      sla_cycles:@cycles,lifecycle_pauses:MemoryRows.new do |values|
        ClockFixture.new(values.merge(sla_cycle_id: values[:sla_cycle]&.id,ended_at:nil))
      end)
    definition = clock_policy_definition
    @version=ClockFixture.new(id:40,definition:definition,rules:JrcServiceDesk::LifecycleRules.new(definition))
    @actor=Object.new
  end
  def clock_policy_definition(schema=1)
    clocks={'first_response'=>'stop','resolution'=>'complete'}
    clocks['attendance']='stop' if schema==2
    sla={'mode'=>'calendar_snapshot','initial_start'=>'opened_at'}
    sla['escalation_policy']={} if schema==2
    {'schema_version'=>schema,'transitions'=>[
      {'key'=>'resolve','action'=>'resolve','from_status_ids'=>[1],'to_status_id'=>2,
       'requirements'=>{'note'=>true,'solution'=>true,'evidence'=>false,'classification'=>false,'fields'=>{}},
       'clocks'=>clocks,'end_pause'=>true}],
     'pause_reasons'=>[{'code'=>'customer','name'=>'Explicit customer wait','status_ids'=>[3],
       'clocks'=>schema==2 ? ['attendance','resolution'] : ['resolution']}],
     'reopen'=>{'allowed'=>true,'window_seconds'=>86400,'anchor_action'=>'resolve','expired'=>'deny',
       'sla_cycle'=>'continue_cycle','inactive_time'=>'exclude','resume_clocks'=>['resolution'],'new_cycle_snapshot'=>'same_snapshot'},
     'sla'=>sla}
  end
  def attendance_policy!
    definition=clock_policy_definition(2)
    @version.definition=definition
    @version.rules=JrcServiceDesk::LifecycleRules.new(definition)
    @snapshot.policy_conditions['clock_budgets_seconds']['attendance']=14400
  end
  def run_engine(action, at:, reason:nil, reopening:nil, effects:{'first_response'=>'keep','resolution'=>'keep'}, end_pause:false)
    rule={'action'=>action,'clocks'=>effects,'end_pause'=>end_pause}
    JrcServiceDesk::LifecycleClocks.new(ticket:@ticket,version:@version,actor:@actor,now:at).run!(rule:rule,reason:reason,reopening:reopening)
  end
  def clock(kind); @cycles.first.sla_clocks.find_by(kind:kind); end
  def reopening(choice='continue_cycle', inactive='exclude')
    {'sla_cycle'=>choice,'inactive_time'=>inactive,'resume_clocks'=>['resolution'],'new_cycle_snapshot'=>'same_snapshot'}
  end
  def resolve(at=@start+3600)
    run_engine('resolve',at:at,effects:{'first_response'=>'stop','resolution'=>'complete'},end_pause:true)
  end
  def test_resolve_records_actual_completion_not_inferred_first_response
    result=resolve
    assert_equal 'completed',clock('resolution').state
    assert_equal @start+3600,clock('resolution').achieved_at
    assert_equal true,clock('resolution').met?
    assert_equal 'stopped',clock('first_response').state
    assert_nil clock('first_response').met?
    assert_equal 'calendar_snapshot',result['mode']
  end
  def test_pause_selected_clock_then_resume_excludes_interval
    result=run_engine('pause',at:@start+3600,reason:{'code'=>'customer','clocks'=>['resolution']})
    assert_equal 'paused',clock('resolution').state
    assert_equal 'running',clock('first_response').state
    assert_equal 3600,clock('resolution').elapsed_seconds
    assert_equal ['resolution'],@ticket.lifecycle_pauses.first.clocks
    run_engine('resume',at:@start+7200,end_pause:true)
    assert_equal 'running',clock('resolution').state
    assert_equal 3600,clock('resolution').elapsed_seconds
    assert_equal Time.iso8601('2026-09-29T13:00:00Z'),clock('resolution').due_at
    assert_equal @start+7200,@ticket.lifecycle_pauses.first.ended_at
    assert_equal @actor,@ticket.lifecycle_pauses.first.ended_by_membership
    assert_equal 1,result['cycle_id']
  end
  def test_waiting_does_not_imply_clock_pause
    run_engine('pause',at:@start+3600,reason:{'code'=>'non_suspensive','clocks'=>[]})
    assert_equal %w[running running],@cycles.first.sla_clocks.map(&:state)
    run_engine('resume',at:@start+7200,end_pause:true)
    assert_equal 7200,clock('resolution').elapsed_seconds
  end
  def test_reopen_continue_excluding_inactive_time_preserves_cycle_and_prior_event_values
    event=resolve
    run_engine('reopen',at:@start+7200,reopening:reopening)
    assert_equal 1,@cycles.size
    assert_equal 'running',clock('resolution').state
    assert_equal 3600,clock('resolution').elapsed_seconds
    assert_nil clock('resolution').achieved_at
    assert_equal Time.iso8601('2026-09-29T13:00:00Z'),clock('resolution').due_at
    assert_equal 'completed',event['clocks'].find { |c| c['kind']=='resolution' }['state']
  end
  def test_reopen_continue_counting_inactive_time_consumes_working_duration
    resolve
    run_engine('reopen',at:@start+7200,reopening:reopening('continue_cycle','count'))
    assert_equal 7200,clock('resolution').elapsed_seconds
    assert_equal Time.iso8601('2026-09-28T20:00:00Z'),clock('resolution').due_at
  end
  def test_reopen_new_cycle_preserves_old_identity_and_restarts_explicit_targets
    resolve; old=@cycles.first
    result=run_engine('reopen',at:@start+7200,reopening:reopening('new_cycle'))
    assert_equal 2,@cycles.size
    assert_equal 2,@cycles.first.number
    assert_equal 0,clock('resolution').elapsed_seconds
    assert_equal Time.iso8601('2026-09-29T14:00:00Z'),clock('resolution').due_at
    assert_equal 'completed',old.sla_clocks.find_by(kind:'resolution').state
    assert_equal old.id,result['previous_cycle']['id']
  end
  def test_reopening_cannot_fabricate_a_missing_previous_cycle
    assert_raises(JrcServiceDesk::LifecycleDependencyError) { run_engine('reopen',at:@start+1,reopening:reopening) }
    assert_equal 0,@cycles.size
  end
  def test_duplicate_pause_and_resume_without_pause_are_rejected
    assert_raises(ArgumentError) { run_engine('resume',at:@start+1,end_pause:true) }
    run_engine('pause',at:@start+3600,reason:{'code'=>'x','clocks'=>['resolution']})
    assert_raises(ArgumentError) { run_engine('pause',at:@start+7200,reason:{'code'=>'x','clocks'=>['resolution']}) }
    assert_raises(ArgumentError) { run_engine('close',at:@start+7200,end_pause:false) }
  end
  def test_non_applicable_policy_records_pause_without_creating_synthetic_clocks
    @version.definition={'sla'=>{'mode'=>'not_applicable','initial_start'=>'opened_at'}}
    result=run_engine('pause',at:@start+1,reason:{'code'=>'x','clocks'=>[]})
    assert_equal 0,@cycles.size
    assert_equal 'not_applicable',result['mode']
    run_engine('resume',at:@start+2,end_pause:true)
    assert_equal @start+2,@ticket.lifecycle_pauses.first.ended_at
  end
  def test_pinned_schema_two_preserves_three_clocks_and_pauses_only_selected_work_clocks
    attendance_policy!
    effects={'first_response'=>'keep','attendance'=>'keep','resolution'=>'keep'}
    run_engine('pause',at:@start+3600,effects:effects,reason:{'code'=>'customer','clocks'=>['attendance','resolution']})
    assert_equal %w[attendance first_response resolution],@cycles.first.sla_clocks.map(&:kind).sort
    assert_equal 'paused',clock('attendance').state
    assert_equal 'paused',clock('resolution').state
    assert_equal 'running',clock('first_response').state
    assert_equal 3600,clock('attendance').elapsed_seconds
    run_engine('resume',at:@start+7200,effects:effects,end_pause:true)
    assert_equal 'running',clock('attendance').state
    assert_equal 3600,clock('attendance').elapsed_seconds
    assert_equal 3600,clock('resolution').elapsed_seconds
    assert_equal 7200,clock('first_response').elapsed_seconds
    assert_equal Time.iso8601('2026-09-28T17:00:00Z'),clock('attendance').due_at
    assert_equal ['attendance','resolution'],@ticket.lifecycle_pauses.first.clocks
  end
  def test_pinned_schema_two_rejects_a_snapshot_missing_the_attendance_clock
    attendance_policy!
    @snapshot.policy_conditions['clock_budgets_seconds'].delete('attendance')
    effects={'first_response'=>'keep','attendance'=>'keep','resolution'=>'keep'}
    assert_raises(JrcServiceDesk::LifecycleDependencyError) { run_engine('work_status',at:@start+1,effects:effects) }
    assert_equal 0,@cycles.size
  end
  def test_explicit_resolution_preserves_three_clocks_without_inferred_attendance_or_first_response
    attendance_policy!
    result=run_engine('resolve',at:@start+3600,effects:@version.rules.rule('resolve').fetch('clocks'),end_pause:true)
    assert_equal 'completed',clock('resolution').state
    assert_equal 'stopped',clock('attendance').state
    assert_equal 'stopped',clock('first_response').state
    assert_nil clock('attendance').met?
    assert_nil clock('first_response').met?
    assert_equal %w[attendance first_response resolution],result['clocks'].map { |item| item['kind'] }.sort
  end
end

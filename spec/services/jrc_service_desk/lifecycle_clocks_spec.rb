# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'Lifecycle clocks using explicit real TZInfo/calendar snapshots', type: :service do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  include ActiveSupport::Testing::TimeHelpers

  before { travel_to Time.iso8601('2026-09-28T12:00:00Z') }
  after { travel_back }

  it 'denies missing or legacy unsupported calendars and leaves no partial policy/event/cycle' do
    lc_publish(definition: lc_definition(tracked: true)); row = sd_ticket(opened_at: Time.current)
    expect { lc_execute(row, 'pause', reason_code: 'customer') }.to raise_error(JrcServiceDesk::LifecycleDependencyError)
    expect(row.reload.lifecycle_policy_version_id).to be_nil
    expect(row.sla_cycles.count).to eq(0)
    expect(row.lifecycle_transitions.count).to eq(0)
  end

  it 'pauses only the selected clock, records both ends and shifts the real deadline on resume' do
    lc_publish(definition: lc_definition(tracked: true)); row = sd_ticket(opened_at: Time.current); lc_snapshot(row)
    travel 1.hour
    lc_execute(row, 'pause', reason_code: 'customer')
    cycle = row.sla_cycles.last
    expect(cycle.sla_clocks.find_by!(kind: 'first_response').state).to eq('running')
    resolution = cycle.sla_clocks.find_by!(kind: 'resolution')
    expect(resolution.state).to eq('paused')
    expect(resolution.elapsed_seconds.to_i).to eq(3600)
    previous_deadline = resolution.due_at
    travel 1.hour
    lc_execute(row, 'resume')
    expect(resolution.reload.state).to eq('running')
    expect(resolution.elapsed_seconds.to_i).to eq(3600)
    expect(resolution.due_at).to be > previous_deadline
    expect(row.lifecycle_pauses.last.ended_at).to eq(Time.current)
    expect(cycle.sla_clocks.find_by!(kind: 'first_response').met?).to be_nil
  end

  it 'a waiting status with an explicit empty clock list never automatically pauses SLA' do
    rules = lc_definition(tracked: true); rules['pause_reasons'].first['clocks'] = []
    lc_publish(definition: rules); row = sd_ticket(opened_at: Time.current); lc_snapshot(row)
    lc_execute(row, 'pause', reason_code: 'customer')
    expect(row.reload.status.phase).to eq('waiting')
    expect(row.sla_cycles.last.sla_clocks.pluck(:state)).to eq(%w[running running])
  end

  %w[continue_cycle new_cycle].each do |choice|
    it "uses configured #{choice} on reopening and preserves previous evidence" do
      lc_publish(definition: lc_definition(tracked: true, cycle: choice)); row = sd_ticket(opened_at: Time.current); lc_snapshot(row)
      travel 1.hour
      resolved = lc_execute(row, 'resolve')
      first = row.sla_cycles.last
      expect(first.sla_clocks.find_by!(kind: 'resolution').state).to eq('completed')
      travel 1.hour
      reopened = lc_execute(row, 'reopen')
      expect(reopened.payload.dig('sla', 'reopening', 'sla_cycle')).to eq(choice)
      expect(row.sla_cycles.count).to eq(choice == 'new_cycle' ? 2 : 1)
      active = row.sla_cycles.last.sla_clocks.find_by!(kind: 'resolution')
      expect(active.state).to eq('running')
      expect(active.elapsed_seconds.to_i).to eq(choice == 'new_cycle' ? 0 : 3600)
      expect(resolved.reload.payload.dig('sla', 'clocks').find { |clock| clock['kind'] == 'resolution' }['state']).to eq('completed')
      expect(row.reload.status.phase).to eq('open')
    end
  end

  it 'honors calendar holiday/exception precedence and rejects ambiguous DST boundaries' do
    cal = JrcServiceDesk::SnapshotCalendar.new(timezone: 'America/Sao_Paulo', conditions: {
      'format' => 'jrc-sd-snapshot-calendar-v1', 'weekly' => (1..7).to_h { |day| [day.to_s, day <= 5 ? [['09:00', '17:00']] : []] },
      'holidays' => ['2026-09-28'], 'exceptions' => { '2026-09-28' => [['10:00', '12:00']] } })
    expect(cal.elapsed(Time.iso8601('2026-09-28T12:00:00Z'), Time.iso8601('2026-09-28T20:00:00Z'))).to eq(7200)
    ambiguous = JrcServiceDesk::SnapshotCalendar.new(timezone: 'America/New_York', conditions: {
      'format' => 'jrc-sd-snapshot-calendar-v1', 'weekly' => (1..7).to_h { |day| [day.to_s, [['01:30', '02:30']]] }, 'holidays' => [], 'exceptions' => {} })
    expect { ambiguous.advance(Time.iso8601('2026-11-01T04:00:00Z'), 60) }.to raise_error(JrcServiceDesk::LifecycleDependencyError)
  end
end

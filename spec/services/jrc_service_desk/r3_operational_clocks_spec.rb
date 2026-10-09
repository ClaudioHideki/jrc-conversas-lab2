# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk::EvaluateClocksService, type: :service do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  include ActiveSupport::Testing::TimeHelpers

  let(:definition) do
    lc_definition(tracked: true).tap do |value|
      value['schema_version'] = 2
      value['sla']['escalation_policy'] = {}
      completing_actions = %w[resolve work_status]
      value['transitions'].each do |transition|
        transition['clocks']['attendance'] = completing_actions.include?(transition['action']) ? 'complete' : 'keep'
      end
      value['pause_reasons'].first['clocks'] = %w[attendance resolution]
      value['reopen']['resume_clocks'] = %w[attendance resolution]
    end
  end
  let(:ticket) { sd_ticket(opened_at: Time.current) }
  let(:snapshot_attributes) do
    sd_snapshot_attributes.merge(
      policy_conditions: { clock_budgets_seconds: { first_response: 7_200, attendance: 3_600, resolution: 28_800 } },
      calendar_conditions: { format: 'jrc-sd-snapshot-calendar-v1', weekly: (1..7).to_h { |day| [day.to_s, [['09:00', '17:00']]] },
                             holidays: [], exceptions: {} }
    )
  end

  before { travel_to Time.iso8601('2026-09-28T12:00:00Z') }

  it 'requires the third explicit budget and rolls back every transition if it is absent' do
    lc_publish(definition: definition)
    lc_snapshot(ticket)
    expect { lc_execute(ticket, 'pause', reason_code: 'customer') }.to raise_error(JrcServiceDesk::LifecycleDependencyError)
    expect(ticket.reload.sla_cycles).to be_empty
    expect(ticket.lifecycle_policy_version_id).to be_nil
  end

  it 'rejects a third clock hidden in a version one policy instead of silently expanding it' do
    legacy = lc_definition(tracked: true)
    legacy['transitions'].first['clocks']['attendance'] = 'keep'
    expect { JrcServiceDesk::LifecycleRules.new(legacy) }.to raise_error(ArgumentError)
    expect(JrcServiceDesk::LifecycleRules.new(definition).clock_kinds).to eq(%w[first_response attendance resolution])
  end

  it 'rejects publishing escalation targets outside the explicit account unit without binding a version' do
    foreign = create(:jrc_sd_queue, unit: sd_other_unit)
    definition['sla']['escalation_policy'] = { 'enabled' => true,
                                               'thresholds' => [{ 'percent' => 70, 'queue_id' => foreign.id, 'team_id' => nil }] }
    expect do
      expect { lc_publish(definition: definition) }.to raise_error(ActiveRecord::RecordNotFound)
    end.not_to change(JrcServiceDesk::LifecyclePolicyVersion, :count)
  end

  it 'completes attendance only through the explicitly published work transition, never first response' do
    lc_publish(definition: definition)
    sd_as_admin!
    JrcServiceDesk::RecordSlaSnapshotService.new(user_context: sd_context).call(ticket_id: ticket.id, attributes: snapshot_attributes)
    travel 20.minutes
    lc_execute(ticket, 'work_status')
    clocks = ticket.sla_cycles.last.sla_clocks
    expect(clocks.pluck(:kind).sort).to eq(%w[attendance first_response resolution])
    expect(clocks.find_by!(kind: 'attendance').achieved_at).to eq(Time.current)
    expect(clocks.find_by!(kind: 'first_response').state).to eq('running')
    expect(clocks.find_by!(kind: 'resolution').state).to eq('running')
    expect(clocks.find_by!(kind: 'attendance').elapsed_seconds).to eq(1200)
  end

  it 'preserves the real attendance interval through pause, inspection and resumption' do
    lc_publish(definition: definition)
    sd_as_admin!
    JrcServiceDesk::RecordSlaSnapshotService.new(user_context: sd_context).call(ticket_id: ticket.id, attributes: snapshot_attributes)
    travel 30.minutes
    lc_execute(ticket, 'pause', reason_code: 'customer')
    clock = ticket.sla_cycles.last.sla_clocks.find_by!(kind: 'attendance')
    prior_deadline = clock.due_at
    travel 2.hours
    before = clock.attributes
    projected = JrcServiceDesk::ClockProjection.new(clock).call
    expect(projected.values_at(:elapsed_seconds, :remaining_seconds, :breached)).to eq([1800.0, 1800.0, false])
    expect(clock.reload.attributes).to eq(before)
    lc_execute(ticket, 'resume')
    expect(clock.reload.due_at).to eq(prior_deadline + 2.hours)
    expect(clock.state).to eq('running')
  end

  it 'records crossed thresholds once with immutable clock proof and creates no external delivery' do
    definition['sla']['escalation_policy'] = { 'enabled' => true,
                                               'thresholds' => [{ 'percent' => 70, 'queue_id' => nil, 'team_id' => nil }] }
    lc_publish(definition: definition)
    sd_as_admin!
    JrcServiceDesk::RecordSlaSnapshotService.new(user_context: sd_context).call(ticket_id: ticket.id, attributes: snapshot_attributes)
    lc_execute(ticket, 'pause', reason_code: 'customer')
    lc_execute(ticket, 'resume')
    travel 50.minutes
    command = described_class.new(user_context: sd_context)
    command.call(ticket_id: ticket.id)
    command.call(ticket_id: ticket.id)
    events = ticket.ticket_events.where(event_type: 'clock_threshold_reached')
    expect(events.count).to eq(1)
    expect(events.first.data.values_at('clock_kind', 'percent', 'budget_seconds', 'elapsed_seconds')).to eq(['attendance', 70, 3600, 3000.0])
    expect(events.first.visibility).to eq('internal')
    expect(JrcServiceDesk::NotificationDelivery.count).to eq(0)
  end

  it 'records a real violation after a 100 percent threshold without overwriting its earlier deadline proof' do
    definition['sla']['escalation_policy'] = { 'enabled' => true,
                                               'thresholds' => [{ 'percent' => 100, 'queue_id' => nil, 'team_id' => nil }] }
    lc_publish(definition: definition)
    sd_as_admin!
    JrcServiceDesk::RecordSlaSnapshotService.new(user_context: sd_context).call(ticket_id: ticket.id, attributes: snapshot_attributes)
    lc_execute(ticket, 'pause', reason_code: 'customer')
    lc_execute(ticket, 'resume')
    travel 60.minutes
    command = described_class.new(user_context: sd_context)
    command.call(ticket_id: ticket.id)
    proof = ticket.ticket_events.find_by!(event_type: 'clock_threshold_reached').data
    expect(proof['breached']).to be(false)
    travel 1.minute
    command.call(ticket_id: ticket.id)
    command.call(ticket_id: ticket.id)
    violation = ticket.ticket_events.where(event_type: 'clock_violated').sole
    expect(violation.data['clock_kind']).to eq('attendance')
    expect(violation.data['elapsed_seconds']).to eq(3660.0)
    expect(violation.data['due_at']).to eq(proof['due_at'])
    expect(ticket.ticket_events.where(event_type: 'clock_threshold_reached').sole.data).to eq(proof)
  end

  it 'does not monitor or escalate OFF policies, even after the entire budget is exhausted' do
    definition['sla']['escalation_policy'] = { 'enabled' => false,
                                               'thresholds' => [{ 'percent' => 100, 'queue_id' => nil, 'team_id' => nil }] }
    lc_publish(definition: definition)
    sd_as_admin!
    JrcServiceDesk::RecordSlaSnapshotService.new(user_context: sd_context).call(ticket_id: ticket.id, attributes: snapshot_attributes)
    lc_execute(ticket, 'pause', reason_code: 'customer')
    lc_execute(ticket, 'resume')
    travel 2.hours
    described_class.new(user_context: sd_context).call(ticket_id: ticket.id)
    expect(ticket.ticket_events.where(event_type: 'clock_threshold_reached')).to be_empty
    expect(ticket.ticket_events.where(event_type: 'clock_violated')).to be_empty
  end

  it 'refuses monitoring after the original unit grant is revoked' do
    ticket
    sd_membership.update!(active: false)
    expect { described_class.new(user_context: sd_context).call(ticket_id: ticket.id) }
      .to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'still rejects an OLA pause policy without an explicit boolean' do
    queue = create(:jrc_sd_queue, unit: sd_unit)
    row = ticket.ola_clocks.new(account: sd_account, unit: sd_unit, queue: queue, budget_seconds: 60,
                                time_basis: 'calendar', state: 'running', started_at: Time.current, anchor_at: Time.current,
                                due_at: 1.minute.from_now, policy_revision: 'a' * 64, pause_waiting: nil)
    expect(row).not_to be_valid
    expect(row.errors[:pause_waiting]).to be_present
  end
end

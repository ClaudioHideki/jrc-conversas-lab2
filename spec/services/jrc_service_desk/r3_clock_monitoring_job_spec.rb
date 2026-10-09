# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk::ClockMonitoringJob do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  include ActiveSupport::Testing::TimeHelpers

  let(:ticket) { sd_ticket(opened_at: Time.current) }
  let(:automatic_policy) do
    { 'enabled' => true, 'automatic' => true, 'execution_account_user_id' => sd_account_user.id,
      'thresholds' => [{ 'percent' => 70, 'queue_id' => nil, 'team_id' => nil }] }
  end
  let(:definition) do
    lc_definition(tracked: true).tap do |value|
      value['schema_version'] = 2
      value['sla']['escalation_policy'] = automatic_policy
      value['transitions'].each { |row| row['clocks']['attendance'] = 'keep' }
      value['pause_reasons'].first['clocks'] = %w[attendance resolution]
      value['reopen']['resume_clocks'] = %w[attendance resolution]
    end
  end
  let(:snapshot_attributes) do
    sd_snapshot_attributes.merge(
      policy_conditions: { clock_budgets_seconds: { first_response: 7200, attendance: 3600, resolution: 28_800 } },
      calendar_conditions: { format: 'jrc-sd-snapshot-calendar-v1', weekly: (1..7).to_h { |day| [day.to_s, [['09:00', '17:00']]] },
                             holidays: [], exceptions: {} }
    )
  end

  before do
    travel_to(Time.iso8601('2026-09-28T12:00:00Z'))
    sd_as_admin!
  end

  def start_clocks
    lc_publish(definition: definition)
    JrcServiceDesk::RecordSlaSnapshotService.new(user_context: sd_context).call(ticket_id: ticket.id, attributes: snapshot_attributes)
    lc_execute(ticket, 'pause', reason_code: 'customer')
    lc_execute(ticket, 'resume')
    ticket.sla_cycles.last.sla_clocks.find_by!(kind: 'attendance')
  end

  def monitoring_events
    ticket.ticket_events.where(event_type: %w[clock_threshold_reached clock_violated])
  end

  it 'keeps manual and legacy policies OFF for scheduling even after a real threshold has elapsed' do
    automatic_policy.delete('automatic')
    automatic_policy.delete('execution_account_user_id')
    start_clocks
    travel 50.minutes
    expect { described_class.perform_now }.not_to change(JrcServiceDesk::TicketEvent, :count)
    expect(monitoring_events).to be_empty
    JrcServiceDesk::EvaluateClocksService.new(user_context: sd_context).call(ticket_id: ticket.id)
    expect(monitoring_events.pluck(:event_type)).to eq(['clock_threshold_reached'])
  end

  it 'runs the native monitored clock under the exact published executor and independently reads the deduplicated proof' do
    clock = start_clocks
    travel 50.minutes
    expect { described_class.perform_now }.not_to change(Message, :count)
    described_class.perform_now
    event = JrcServiceDesk::TicketEvent.where(ticket: ticket, event_type: 'clock_threshold_reached').sole
    expect(event.actor_membership_id).to eq(sd_membership.id)
    expect(event.data).to include('clock_id' => clock.id, 'clock_kind' => 'attendance', 'percent' => 70,
                                'elapsed_seconds' => 3000.0, 'policy_digest' => clock.sla_cycle.lifecycle_policy_version.digest)
    expect(JrcServiceDesk::NotificationDelivery.count).to eq(0)
  end

  it 'does not borrow another clock or its manual policy when evaluating one automatically approved clock' do
    clock = start_clocks
    queue = create(:jrc_sd_queue, unit: sd_unit, ola_budget_seconds: 60, ola_time_basis: 'calendar', ola_pause_waiting: false,
                                  ola_escalation_policy: { enabled: true, thresholds: [{ percent: 70, queue_id: nil, team_id: nil }] })
    ticket.reload.update!(queue: queue)
    ola = JrcServiceDesk::OlaTracker.sync!(ticket)
    travel 50.minutes
    JrcServiceDesk::EvaluateClocksService.new(user_context: sd_context).evaluate_clock(
      kind: 'sla', clock_id: clock.id, policy_digest: clock.sla_cycle.lifecycle_policy_version.digest
    )
    expect(monitoring_events.pluck(Arel.sql("data->>'clock_kind'"))).to eq(['attendance'])
    described_class.perform_now
    expect(monitoring_events.count).to eq(1)
    expect(ola.reload.state).to eq('running')
    expect(JrcServiceDesk::ClockProjection.new(ola).call[:breached]).to be(true)
  end

  it 'rechecks revoked unit, actor role and module feature without recording an automatic effect' do
    start_clocks
    travel 50.minutes
    sd_membership.update!(active: false)
    expect { described_class.perform_now }.not_to change(JrcServiceDesk::TicketEvent, :count)
    sd_membership.update!(active: true)
    role = create(:custom_role, account: sd_account, permissions: ['jrc_service_desk_module_view'])
    sd_account_user.update!(custom_role: role)
    expect { described_class.perform_now }.not_to change(JrcServiceDesk::TicketEvent, :count)
    sd_account_user.update!(custom_role: nil, role: :administrator)
    sd_account.disable_features!('jrc_service_desk')
    expect { described_class.perform_now }.not_to change(JrcServiceDesk::TicketEvent, :count)
    expect(monitoring_events).to be_empty
  end

  it 'does not reuse a superseded SLA version for an automatic effect on a pinned historical cycle' do
    clock = start_clocks
    old_version = clock.sla_cycle.lifecycle_policy_version
    lc_publish(definition: definition, expected_version: 1)
    travel 50.minutes
    expect { described_class.perform_now }.not_to change(JrcServiceDesk::TicketEvent, :count)
    expect(ticket.reload.lifecycle_policy_version_id).to eq(old_version.id)
    expect(monitoring_events).to be_empty
  end

  it 'rejects an explicit foreign executor and an executor without this unit grant during publication' do
    versions_before = JrcServiceDesk::LifecyclePolicyVersion.count
    foreign = create(:account_user, account: sd_foreign_account, role: :administrator)
    automatic_policy['execution_account_user_id'] = foreign.id
    expect { lc_publish(definition: definition) }.to raise_error(ActiveRecord::RecordNotFound)
    member = create(:account_user, account: sd_account, role: :administrator)
    automatic_policy['execution_account_user_id'] = member.id
    expect { lc_publish(definition: definition) }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcServiceDesk::LifecyclePolicyVersion.count).to eq(versions_before)
    expect(JrcServiceDesk::LifecyclePolicyVersion.where(account: sd_account).count).to eq(0)
  end

  it 'requires the automatic switch, native executor and finite canonical identifiers without inventing a default' do
    expect(JrcServiceDesk::ClockEscalationPolicy.new({}).automatic?).to be(false)
    expect(JrcServiceDesk::ClockEscalationPolicy.new(automatic_policy.except('automatic', 'execution_account_user_id')).automatic?).to be(false)
    expect { JrcServiceDesk::ClockEscalationPolicy.new(automatic_policy.except('execution_account_user_id')) }.to raise_error(ArgumentError)
    expect { JrcServiceDesk::ClockEscalationPolicy.new(automatic_policy.merge('automatic' => 'true')) }.to raise_error(ArgumentError)
    expect { JrcServiceDesk::ClockEscalationPolicy.new(automatic_policy.merge('execution_account_user_id' => '01')) }.to raise_error(ArgumentError)
    expect { JrcServiceDesk::ClockEscalationPolicy.new(automatic_policy.merge('headers' => {})) }.to raise_error(ArgumentError)
    expect { JrcServiceDesk::ClockEscalationPolicy.new(automatic_policy.merge('automatic' => false, 'execution_account_user_id' => false)) }
      .to raise_error(ArgumentError)
    parsed = JrcServiceDesk::ClockEscalationPolicy.new(automatic_policy.merge('execution_account_user_id' => sd_account_user.id.to_s))
    expect(parsed.execution_account_user_id).to eq(sd_account_user.id)
  end

  it 'observes calendar time only inside the published business intervals and preserves an explicit paused clock' do
    clock = start_clocks
    travel 20.minutes
    lc_execute(ticket, 'pause', reason_code: 'customer')
    travel 3.hours
    described_class.perform_now
    paused_events = monitoring_events.where("data->>'clock_kind' IN (?)", %w[attendance resolution])
    expect(paused_events).to be_empty
    expect(clock.reload.state).to eq('paused')
    expect(JrcServiceDesk::ClockProjection.new(clock).call[:elapsed_seconds]).to eq(1200)
    independent = monitoring_events.where("data->>'clock_kind' = ?", 'first_response')
    expect(independent.order(:event_type).pluck(:event_type)).to eq(%w[clock_threshold_reached clock_violated])
  end

  it 'does not turn wall clock hours outside the snapshot calendar into a threshold' do
    travel_to(Time.iso8601('2026-09-28T21:00:00Z'))
    clock = start_clocks
    travel 10.hours
    described_class.perform_now
    expect(JrcServiceDesk::ClockProjection.new(clock.reload).call[:elapsed_seconds]).to eq(0)
    expect(monitoring_events).to be_empty
  end

  it 'rejects a stale exact-clock digest without falling back to the manual evaluator' do
    clock = start_clocks
    travel 50.minutes
    expect do
      JrcServiceDesk::EvaluateClocksService.new(user_context: sd_context).evaluate_clock(
        kind: 'sla', clock_id: clock.id, policy_digest: '0' * 64
      )
    end.to raise_error(JrcServiceDesk::IdempotencyConflict)
    expect(monitoring_events).to be_empty
  end

  it 'rechecks the current active unit before the scheduled native mutation' do
    start_clocks
    travel 50.minutes
    sd_unit.update!(active: false)
    expect { described_class.perform_now }.not_to change(JrcServiceDesk::TicketEvent, :count)
    expect(monitoring_events).to be_empty
  end

  context 'with an explicit automatically monitored OLA' do
    let(:queue) do
      create(:jrc_sd_queue, unit: sd_unit, ola_budget_seconds: 60, ola_time_basis: 'calendar', ola_pause_waiting: false,
                            ola_escalation_policy: automatic_policy)
    end

    def start_ola
      ticket.update!(queue: queue)
      JrcServiceDesk::OlaTracker.sync!(ticket)
    end

    it 'monitors the real queue clock and persists one immutable breach proof without a customer delivery' do
      clock = start_ola
      travel 61.seconds
      described_class.perform_now
      described_class.perform_now
      rows = monitoring_events.order(:event_type)
      expect(rows.pluck(:event_type)).to eq(%w[clock_threshold_reached clock_violated])
      expect(rows.all? { |row| row.actor_membership_id == sd_membership.id && row.data['clock_id'] == clock.id }).to be(true)
      expect(rows.all? { |row| row.data['clock_kind'] == 'ola' && row.data['policy_digest'] == clock.policy_revision }).to be(true)
      expect(Message.count).to eq(0)
    end

    it 'stops a queued policy binding after its queue configuration is changed or disabled' do
      clock = start_ola
      travel 61.seconds
      queue.update!(ola_budget_seconds: 120)
      expect { described_class.perform_now }.not_to change(JrcServiceDesk::TicketEvent, :count)
      expect(clock.reload.budget_seconds).to eq(60)
      queue.update!(ola_budget_seconds: 60, active: false)
      expect { described_class.perform_now }.not_to change(JrcServiceDesk::TicketEvent, :count)
    end

    it 'rejects a different actor for the same exact clock instead of borrowing its published grants' do
      clock = start_ola
      member = create(:account_user, account: sd_account, role: :administrator)
      create(:jrc_sd_membership, account: sd_account, unit: sd_unit, account_user: member)
      context = { account: sd_account, user: member.user, account_user: member }
      travel 61.seconds
      expect do
        JrcServiceDesk::EvaluateClocksService.new(user_context: context).evaluate_clock(kind: 'ola', clock_id: clock.id,
                                                                                    policy_digest: clock.policy_revision)
      end.to raise_error(Pundit::NotAuthorizedError)
      expect(monitoring_events).to be_empty
    end
  end
end

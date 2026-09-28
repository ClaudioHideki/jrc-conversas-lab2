# frozen_string_literal: true

# Explicit fixtures only. Never loaded by application code or used as default policies.
module JrcServiceDeskLifecycleFixtures
  def lc_statuses
    @lc_statuses ||= { open: sd_status }.merge(%i[waiting resolved closed cancelled working].to_h do |name|
      [name, create(:jrc_sd_status, unit: sd_unit, initial: false, phase: name == :working ? 'open' : name.to_s, name: "Fixture #{name}")]
    end)
  end

  def lc_definition(tracked: false, cycle: 'continue_cycle')
    s = lc_statuses
    pairs = { 'pause' => [%i[open working], :waiting], 'resume' => [[:waiting], :working],
              'resolve' => [%i[open working waiting], :resolved], 'close' => [[:resolved], :closed],
              'cancel' => [%i[open working waiting resolved], :cancelled], 'reopen' => [%i[resolved closed cancelled], :open],
              'work_status' => [[:open], :working] }
    { 'schema_version' => 1, 'transitions' => pairs.map do |action, (from, target)|
        { 'key' => action, 'action' => action, 'from_status_ids' => from.map { |v| s[v].id }, 'to_status_id' => s[target].id,
          'requirements' => { 'note' => false, 'solution' => false, 'evidence' => false, 'classification' => false, 'fields' => {} },
          'clocks' => { 'first_response' => tracked && %w[resolve cancel].include?(action) ? 'stop' : 'keep',
                        'resolution' => tracked && action == 'resolve' ? 'complete' : tracked && action == 'cancel' ? 'stop' : 'keep' },
          'end_pause' => %w[resume resolve cancel].include?(action) }
      end,
      'pause_reasons' => [{ 'code' => 'customer', 'name' => 'Fixture customer pause', 'status_ids' => [s[:waiting].id], 'clocks' => tracked ? ['resolution'] : [] }],
      'reopen' => { 'allowed' => true, 'window_seconds' => 86400, 'anchor_action' => 'resolve', 'expired' => 'deny',
                    'sla_cycle' => cycle, 'inactive_time' => 'exclude', 'resume_clocks' => ['resolution'], 'new_cycle_snapshot' => 'same_snapshot' },
      'sla' => { 'mode' => tracked ? 'calendar_snapshot' : 'not_applicable', 'initial_start' => 'opened_at' } }
  end

  def lc_publish(definition: lc_definition, service: nil, enabled: true, expected_version: 0)
    prior_role = sd_account_user.role
    sd_as_admin!
    JrcServiceDesk::PublishLifecyclePolicyService.new(user_context: sd_context).call(unit_id: sd_unit.id,
      attributes: { name: 'Explicit fixture policy', service_id: service&.id, enabled: enabled,
                    expected_version: expected_version, definition: definition })
  ensure
    sd_account_user.update!(role: prior_role) if prior_role
  end

  def lc_execute(ticket, key, values = {}, request_key: SecureRandom.uuid, **additional)
    values = values.merge(additional)
    ticket.reload
    policy = JrcServiceDesk::LifecycleSelector.new(ticket).applicable
    JrcServiceDesk::LifecycleTransitionService.new(user_context: sd_context).call(ticket_id: ticket.id,
      attributes: { rule_key: key, expected_lock_version: ticket.lock_version, expected_policy_version_id: policy&.id || 1 }.merge(values),
      idempotency_key: request_key)
  end

  def lc_snapshot(ticket)
    settings = sd_snapshot_attributes.merge(policy_conditions: { clock_budgets_seconds: { first_response: 7200, resolution: 28800 } },
      calendar_conditions: { format: 'jrc-sd-snapshot-calendar-v1', weekly: (1..7).to_h { |day| [day.to_s, day <= 5 ? [['09:00', '17:00']] : []] }, holidays: [], exceptions: {} })
    prior = sd_account_user.role
    sd_as_admin!
    JrcServiceDesk::RecordSlaSnapshotService.new(user_context: sd_context).call(ticket_id: ticket.id, attributes: settings)
    ticket.reload.latest_sla_snapshot
  ensure
    sd_account_user.update!(role: prior) if prior
  end
end

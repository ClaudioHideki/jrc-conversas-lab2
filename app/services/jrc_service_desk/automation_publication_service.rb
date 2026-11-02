# frozen_string_literal: true

# All native publications and their receipt share the existing unit transaction.
# Preview deliberately does not enter BaseService#with_unit: that method may
# create an administrative membership, which a pure simulation must never do.
class JrcServiceDesk::AutomationPublicationService < JrcServiceDesk::BaseService
  Result = Struct.new(:publication, :audit_id, keyword_init: true)

  def preview(unit_id:, attributes:, facts: {}, at: nil)
    @context = fresh_context!
    unit = context.unit_scope.find(JrcServiceDesk::Input.id(unit_id))
    composition = JrcServiceDesk::AutomationComposition.new(attributes)
    authorize!(JrcServiceDesk::AutomationPublication.new(account: context.account, unit: unit, **composition.values.slice('kind').symbolize_keys), :create?)
    validation = validate_components!(unit, composition)
    facts = JrcServiceDesk::Input.attributes(facts, JrcServiceDesk::OperationalRuleContract::MATCH_FIELDS)
    JrcServiceDesk::OperationalRuleContract.predicates!(facts.except('form_value'))
    if facts['form_value']
      service = JrcServiceDesk::Service.where(account: context.account, unit: unit).find(JrcServiceDesk::Input.id(composition.values['service_id']))
      raise ArgumentError unless facts['form_value'].is_a?(Hash) && facts['form_value'].size <= 50
      fields = service.form_fields.select { |field| facts['form_value'].key?(field['key']) }
      JrcServiceDesk::CatalogueAnswers.new(fields).validate!(facts['form_value'])
    end
    JrcServiceDesk::OperationalRuleReferences.new(context: context, unit: unit).validate_facts!(facts)
    now = at ? Time.iso8601(at) : Time.current
    simulation = {}
    projected = facts.dup
    %w[priority_matrix routing sla_selection].each do |kind|
      definition = validation[:families][kind]
      next unless definition

      winner = JrcServiceDesk::OperationalRuleMatcher.call(definition['rules'], projected, now: now)
      simulation[kind] = winner && winner.slice('key', 'precedence', 'output')
      projected['priority_id'] = winner['output']['priority_id'] if winner && kind == 'priority_matrix'
      projected.merge!(winner['output'].fetch('classification', {})) if winner && kind == 'routing'
    end
    assignment = nil
    if simulation['routing']
      output = simulation['routing']['output']
      queue_changes = composition.values['definition']['queues'].find { |row| row['id'].to_i == output['queue_id'] }
      assignment = JrcServiceDesk::AutomaticRoutingService.new(user_context: context.to_h).preview(unit_id: unit.id, queue_id: output['queue_id'],
        options: output.fetch('assignment', {}), queue_attributes: queue_changes&.fetch('attributes') || {})
    end
    sla_deadlines = validation[:families].fetch('sla_selection', {}).fetch('rules', []).select { |row| row['key'].start_with?(composition.prefix) }.map do |row|
      snapshot = row['output']['snapshot']
      calendar = JrcServiceDesk::SnapshotCalendar.new(timezone: snapshot['timezone'], conditions: snapshot['calendar_conditions'])
      { key: row['key'], started_at: now.iso8601, due_at: snapshot['policy_conditions']['clock_budgets_seconds'].transform_values { |seconds| calendar.advance(now, seconds).iso8601 } }
    end
    { valid: true, native_versions: validation[:versions], simulation: simulation, assignment: assignment, sla_deadlines: sla_deadlines, historical_tickets_changed: 0,
      effects: { creates_ticket: false, sends_message: false, assigns_member: false, writes_audit: false } }
  end

  def call(unit_id:, attributes:, expected_version:, expected_native_versions:, confirmed:, idempotency_key:)
    raise ArgumentError, 'Explicit publication confirmation required' unless confirmed == true

    composition = JrcServiceDesk::AutomationComposition.new(attributes)
    expected = JrcServiceDesk::Input.version(expected_version)
    fingerprint = JrcServiceDesk::CanonicalJson.digest('attributes' => composition.values, 'expected_version' => expected,
                                                       'expected_native_versions' => expected_native_versions)
    with_unit(unit_id) do |unit|
      values = composition.values
      candidate = JrcServiceDesk::AutomationPublication.new(account: context.account, unit: unit, **values.except('definition').symbolize_keys)
      authorize!(candidate, :create?)
      audit = JrcServiceDesk::ConfigurationAudit.new(context: context, membership: actor_membership, unit: unit)
      prior = audit.prior(idempotency_key)
      if prior
        metadata = audit.metadata(prior)
        raise JrcServiceDesk::IdempotencyConflict unless metadata['resource'] == 'automation_publications' && metadata['fingerprint'] == fingerprint

        row = JrcServiceDesk::AutomationPublication.where(account: context.account, unit: unit).find(prior.auditable_id)
        authorize!(row, :show?)
        validate_capabilities!(unit, composition)
        next Result.new(publication: row, audit_id: prior.id)
      end
      current = JrcServiceDesk::AutomationPublication.where(account: context.account, unit: unit, kind: values['kind'], code: values['code']).order(version: :desc).first
      raise JrcServiceDesk::IdempotencyConflict, 'Composition changed' unless (current&.version || 0) == expected
      if current && current.service_id != values['service_id']
        raise ArgumentError, 'Published service scope is stable; create another code for a different service'
      end
      if current
        removed = current.definition.fetch('families').keys - values['definition']['families'].keys
        old_notifications = current.definition.fetch('notifications').map { |item| notification_key(item) }
        new_notifications = values['definition']['notifications'].map { |item| notification_key(item) }
        raise ArgumentError, 'Retire existing components explicitly instead of omitting them' if removed.any? || (old_notifications - new_notifications).any?
      end
      if values['kind'] == 'lifecycle'
        owner = JrcServiceDesk::AutomationPublication.where(account: context.account, unit: unit, kind: 'lifecycle', service_id: values['service_id']).where.not(code: values['code'])
        raise JrcServiceDesk::IdempotencyConflict, 'This lifecycle scope already has another coordinated policy' if owner.exists?
      end
      validation = validate_components!(unit, composition)
      unless JrcServiceDesk::CanonicalJson.normalize(expected_native_versions) == validation[:versions]
        raise JrcServiceDesk::IdempotencyConflict, 'Native configuration changed; validate again'
      end
      publish_components!(unit, composition, validation, idempotency_key)
      candidate.assign_attributes(definition: values['definition'], version: expected + 1, published_by_membership: actor_membership,
                                  native_versions: native_versions(unit, composition))
      candidate.digest = candidate.expected_digest
      candidate.save!
      receipt = audit.write!(resource: 'automation_publications', record: candidate, action: 'create', before: {},
                              after: candidate.attributes.except('created_at'), key: idempotency_key, fingerprint: fingerprint)
      Result.new(publication: candidate, audit_id: receipt.id)
    end
  end

  def native_versions(unit, composition)
    definition = composition.values['definition']
    result = { 'families' => {}, 'queues' => {}, 'notifications' => {} }
    if definition['lifecycle']
      policy = JrcServiceDesk::LifecyclePolicy.find_by(account: context.account, unit: unit, service_id: composition.values['service_id'])
      result['lifecycle'] = policy&.current_version&.version || 0
    end
    definition['families'].each_key do |kind|
      row = JrcServiceDesk::OperationalRuleVersion.current(account_id: context.account.id, unit_id: unit.id, kind: kind)
      result['families'][kind] = row&.version || 0
    end
    definition['queues'].each do |item|
      row = JrcServiceDesk::Queue.where(account: context.account, unit: unit).find(item['id'])
      result['queues'][row.id.to_s] = JrcServiceDesk::ConfigurationResources.revision('queues', row)
    end
    definition['notifications'].each do |item|
      key = notification_key(item)
      result['notifications'][key] = JrcServiceDesk::NotificationPolicyVersion.where(account: context.account, unit: unit, **item.slice('event_type', 'channel', 'ticket_type_id', 'service_id').symbolize_keys)
        .order(version: :desc).first&.version || 0
    end
    result
  end

  private

  def validate_capabilities!(unit, composition)
    definition = composition.values['definition']
    definition['families'].each_key { |kind| JrcServiceDesk::OperationalRuleAccess.require!(context, kind, unit) }
    raise Pundit::NotAuthorizedError if definition['queues'].any? && !context.capability?(:queues_manage)
    raise Pundit::NotAuthorizedError if definition['notifications'].any? && !context.capability?(:notifications_manage)
    raise Pundit::NotAuthorizedError if definition['lifecycle'] && !context.capability?(:lifecycle_policies_manage)
  end

  def validate_components!(unit, composition)
    validate_capabilities!(unit, composition)
    values = composition.values
    definition = values['definition']
    reference(JrcServiceDesk::Service, values['service_id'], unit) if values['service_id']
    if definition['lifecycle']
      service = JrcServiceDesk::PublishLifecyclePolicyService.new(user_context: context.to_h)
      service.validate_for_preview!(unit: unit, attributes: lifecycle_attributes(composition, 0))
      validate_graph!(unit, definition['lifecycle'])
    end
    validator = JrcServiceDesk::OperationalRuleReferences.new(context: context, unit: unit)
    families = definition['families'].to_h do |kind, _data|
      current = JrcServiceDesk::OperationalRuleVersion.current(account_id: context.account.id, unit_id: unit.id, kind: kind)
      merged = composition.merge_family(kind, current)
      JrcServiceDesk::OperationalRuleContract.validate!(kind, merged)
      merged['rules'].select { |row| row['key'].start_with?(composition.prefix) && row['enabled'] == false }.each do |row|
        JrcServiceDesk::OperationalRuleReferences.new(context: context, unit: unit, active: false).validate_rule!(row)
        if kind == 'sla_selection'
          kinds = definition['lifecycle'] && JrcServiceDesk::LifecycleRules.new(definition['lifecycle']).clock_kinds
          validator.verify_snapshot!(row['output']['snapshot'], clock_kinds: kinds)
        end
      end
      conflicts = JrcServiceDesk::OperationalRuleConditions.conflicts(merged['rules'])
      raise JrcServiceDesk::IdempotencyConflict, 'Possible equal-precedence conflict; choose a distinct precedence' if conflicts.any?

      merged['rules'].select { |row| row['enabled'] != false }.each do |row|
        validator.validate_rule!(row)
        next unless kind == 'sla_selection'

        kinds = definition['lifecycle'] && JrcServiceDesk::LifecycleRules.new(definition['lifecycle']).clock_kinds
        validator.verify_snapshot!(row['output']['snapshot'], clock_kinds: kinds)
      end
      [kind, merged]
    end
    definition['queues'].each do |item|
      queue = JrcServiceDesk::Queue.where(account: context.account, unit: unit).find(item['id'])
      authorize!(queue, :update?)
      native_team(item['attributes']['team_id']) if item['attributes']['team_id']
      queue.assign_attributes(JrcServiceDesk::ConfigurationContract.attributes('queues', item['attributes'], create: false))
      raise ActiveRecord::RecordInvalid, queue unless queue.valid?
    end
    definition['notifications'].each do |item|
      scope = JrcServiceDesk::AutomationPublication.where(account: context.account, unit: unit)
      owners = scope.where(id: scope.group(:kind, :code).select('MAX(id)')).where(enabled: true)
        .where.not(kind: composition.values['kind'], code: composition.values['code'])
      taken = owners.any? do |owner|
        owner.definition.fetch('notifications').any? { |entry| entry['enabled'] && notification_key(entry) == notification_key(item) }
      end
      raise JrcServiceDesk::IdempotencyConflict, 'Notification scope belongs to another enabled coordinated policy' if taken

      values = notification_attributes(item, composition)
      service = JrcServiceDesk::PublishNotificationPolicyService.new(user_context: context.to_h)
      service.validate_for_preview!(unit: unit, attributes: values)
    end
    { versions: native_versions(unit, composition), families: families }
  end

  def publish_components!(unit, composition, validation, request_key)
    definition = composition.values['definition']
    definition['queues'].each_with_index do |item, index|
      JrcServiceDesk::ConfigurationService.new(user_context: context.to_h).update(resource: 'queues', record_id: item['id'], attributes: item['attributes'],
        expected_revision: validation[:versions]['queues'].fetch(item['id'].to_s), idempotency_key: "#{request_key}:queue:#{index}")
    end
    if definition['lifecycle']
      JrcServiceDesk::PublishLifecyclePolicyService.new(user_context: context.to_h).call(unit_id: unit.id,
        attributes: lifecycle_attributes(composition, validation[:versions]['lifecycle']))
    end
    validation[:families].each do |kind, data|
      JrcServiceDesk::PublishOperationalRulesService.new(user_context: context.to_h).call(unit_id: unit.id, kind: kind, definition: data,
        enabled: data['rules'].any? { |row| row['enabled'] != false }, expected_version: validation[:versions]['families'].fetch(kind))
    end
    definition['notifications'].each do |item|
      attributes = notification_attributes(item, composition).merge('expected_version' => validation[:versions]['notifications'].fetch(notification_key(item)))
      JrcServiceDesk::PublishNotificationPolicyService.new(user_context: context.to_h).call(unit_id: unit.id, attributes: attributes)
    end
  end

  def lifecycle_attributes(composition, version)
    composition.values.slice('name', 'service_id', 'enabled').merge('expected_version' => version, 'definition' => composition.values['definition']['lifecycle'])
  end

  def validate_graph!(unit, definition)
    reachable = JrcServiceDesk::TicketStatus.where(account: context.account, unit: unit, active: true, initial: true).pluck(:id)
    raise ArgumentError, 'Configure an authorized initial status first' if reachable.empty?

    transitions = definition.fetch('transitions')
    loop do
      expanded = (reachable + transitions.select { |row| (row['from_status_ids'] & reachable).any? }.map { |row| row['to_status_id'] }).uniq
      break if expanded.sort == reachable.sort

      reachable = expanded
    end
    required = transitions.flat_map { |row| row['from_status_ids'] + [row['to_status_id']] }.uniq
    raise ArgumentError, 'Lifecycle contains unreachable statuses' if (required - reachable).any?
  end

  def notification_attributes(item, composition)
    raise ArgumentError, 'Use individual native notification channels' if item.key?('channel_configurations')
    if composition.values['service_id'] && item['service_id'] != composition.values['service_id']
      raise ArgumentError, 'Notification must retain selected service scope'
    end
    item.merge('enabled' => composition.values['enabled'] && item.fetch('enabled'), 'confirmed' => true, 'expected_version' => 0)
  end

  def notification_key(item)
    JrcServiceDesk::CanonicalJson.digest(item.slice('event_type', 'channel', 'ticket_type_id', 'service_id'))
  end
end

# Operational summaries from the existing audit store. Historic IDs, private
# values and free-text reasons remain stored but are not granted by current sharing.
class JrcRelationship::PortfolioGroupHistory
  ACTIONS = { 'portfolio_group_created' => 'created', 'portfolio_group_updated' => 'updated',
              'portfolio_group_customers_updated' => 'customers', 'configuration_versioned' => 'rules',
              'portfolio_group_history_exported' => 'exported', 'configuration_restored' => 'restored' }.freeze

  def initialize(context)
    @account_id = context.account.id
    @actor_id = context.user.id
  end

  def index(id, page: 1, kind: '', period: nil)
    with_authority(id) do |context, group|
      events = filtered_events(context, group, kind, period)
      number = Integer(page.to_s, 10).clamp(1, 10_000)
      rows = events.order(created_at: :desc, id: :desc).limit(25).offset((number - 1) * 25).to_a
      { payload: present(context, rows), meta: { group_id: group.id, page: number, per_page: 25, total: events.count,
                                                 can_read_rules: context.policy.configure?, projection: 'operational_summary' } }
    end
  end

  def export(id, kind: '', period: nil)
    with_authority(id) do |context, group|
      raise Pundit::NotAuthorizedError unless context.policy.export_history? && JrcRelationship::LocalAccess.group_allowed?(context, group, 'export_history')

      events = filtered_events(context, group, kind, period)
      upper = events.maximum(:id)
      events = upper ? events.where('id <= ?', upper) : events.none
      raise ArgumentError, 'Limit the operational history export to 10000 events' if events.count > 10_000

      rows = []
      events.find_in_batches(batch_size: 100) { |batch| rows.concat(present(context, batch)) }
      context.audit!(group, after: { events: rows.size, scope: "portfolio:#{group.id}", filters: { kind: kind, from: period&.begin, to: period&.end }, format: 'json' }, action: 'portfolio_group_history_exported')
      { version: 1, projection: 'operational_summary', group: { id: group.id, name: group.name },
        exported_at: Time.current.iso8601(6), events: rows }
    end
  end

  private

  def with_authority(id)
    JrcRelationship::PortfolioGroup.transaction do
      JrcRelationship::BatchReviewAuthority.new(account_id: @account_id, actor_id: @actor_id, write: false).call do |context|
        group = JrcRelationship::PortfolioGroupAccess.complete_management!(context, id)
        yield context, group
      end
    end
  end

  def filtered_events(context, group, kind, period)
    raise ArgumentError, 'Invalid portfolio history kind' unless kind == '' || ACTIONS.value?(kind)
    raise Pundit::NotAuthorizedError if %w[rules restored].include?(kind) && !context.policy.configure?

    events = history_events(context, group)
    events = events.where("metadata ->> 'action' = ?", ACTIONS.key(kind)) unless kind.empty?
    period ? events.where(created_at: period) : events
  end

  def history_events(context, group)
    events = resource_events(context, group)
    configuration = JrcRelationship::PortfolioGroupConfiguration.for(group) if context.policy.configure?
    configuration ? events.or(resource_events(context, configuration)) : events
  end

  def resource_events(context, resource)
    JrcCrm::AuditEvent.where(account_id: context.account.id, event_type: 'relationship_updated',
                             resource_type: resource.class.name, resource_id: resource.id)
  end

  def present(context, rows)
    ids = rows.filter_map { |row| row.actor_id if row.actor_type == 'User' }.uniq
    actors = context.assignable_users.where(id: ids).pluck(:id, :name).to_h
    rows.map { |event| present_event(event, actors) }
  end

  def present_event(event, actors)
    after = event.to_value.is_a?(Hash) ? event.to_value : {}
    metadata = event.metadata.is_a?(Hash) ? event.metadata : {}
    actor = { id: event.actor_id, name: actors.fetch(event.actor_id) } if event.actor_type == 'User' && actors.key?(event.actor_id)
    { id: event.id, at: event.created_at.iso8601(6), kind: ACTIONS.fetch(metadata['action'], 'updated'), actor: actor,
      reason_recorded: after['reason'].is_a?(String) && after['reason'].present?, changed_fields: changed_fields(event) }
  end

  def changed_fields(event)
    before = event.from_value.is_a?(Hash) ? event.from_value : {}
    after = event.to_value.is_a?(Hash) ? event.to_value : {}
    if event.resource_type == JrcRelationship::Configuration.name
      before = before['rules'].is_a?(Hash) ? before['rules'] : {}
      after = after['rules'].is_a?(Hash) ? after['rules'] : {}
      fields = JrcRelationship::PortfolioGroupConfiguration::RULES
    else
      fields = JrcRelationship::PortfolioGroups::FIELDS + ['customers']
    end
    fields.reject { |key| before[key] == after[key] }
  end
end

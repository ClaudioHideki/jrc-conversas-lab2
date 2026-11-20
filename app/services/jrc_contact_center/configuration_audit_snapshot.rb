# frozen_string_literal: true

class JrcContactCenter::ConfigurationAuditSnapshot
  FIELDS = {
    'JrcContactCenter::Unit' => %w[code name kind status timezone parent_unit_id],
    'JrcContactCenter::Queue' => %w[unit_id code name service_kind strategy status max_wait_seconds active_from active_until],
    'JrcContactCenter::QueueMembership' => %w[queue_id account_user_id role priority active starts_at ends_at],
    'JrcContactCenter::AccessGrant' => %w[account_user_id team_id eligible allowed denied],
    'JrcContactCenter::TeamState' => %w[team_id active lock_version],
    'JrcContactCenter::RoutingRule' => %w[version rule_key kind source_value target_unit_id target_queue_id priority state starts_at ends_at]
  }.freeze

  def self.capture(record)
    return routing_snapshot(record) if record.is_a?(JrcContactCenter::RoutingRule)

    if record.is_a?(JrcContactCenter::AccessGrant) || record.is_a?(JrcContactCenter::TeamState)
      return { 'attributes' => attributes_for(record), 'scope' => { 'account_id' => record.account_id.to_s } }
    end

    queue = queue_for(record)
    unit = record.is_a?(JrcContactCenter::Unit) ? record : JrcContactCenter::Unit.find_by!(account_id: record.account_id, id: queue.unit_id)
    { 'attributes' => attributes_for(record), 'scope' => scope_for(record, unit, queue) }
  end

  def self.attributes_for(record)
    attributes = record.as_json(only: FIELDS.fetch(record.class.name))
    attributes['settings'] = record.settings.slice('issuer_company_id', 'business_unit_id') if record.is_a?(JrcContactCenter::Unit)
    if record.is_a?(JrcContactCenter::QueueMembership)
      attributes['participates'] = record.role == 'agent'
      attributes['supervises'] = record.role == 'supervisor' || record.settings['supervises'] == true
    end
    attributes
  end

  def self.scope_for(record, unit, queue)
    {
      'account_id' => record.account_id.to_s, 'unit_id' => unit.id.to_s, 'queue_id' => queue&.id&.to_s,
      'issuer_company_id' => unit.settings['issuer_company_id'].presence&.to_s,
      'business_unit_id' => unit.settings['business_unit_id'].presence&.to_s
    }
  end

  def self.routing_snapshot(record)
    queue = JrcContactCenter::Queue.find_by!(account_id: record.account_id, id: record.target_queue_id) if record.target_queue_id
    unit = JrcContactCenter::Unit.find_by!(account_id: record.account_id, id: record.target_unit_id || queue&.unit_id)
    { 'attributes' => attributes_for(record), 'scope' => scope_for(record, unit, queue) }
  end

  def self.queue_for(record)
    return record if record.is_a?(JrcContactCenter::Queue)
    return unless record.is_a?(JrcContactCenter::QueueMembership)

    JrcContactCenter::Queue.find_by!(account_id: record.account_id, id: record.queue_id)
  end
  private_class_method :queue_for, :attributes_for, :scope_for, :routing_snapshot
end

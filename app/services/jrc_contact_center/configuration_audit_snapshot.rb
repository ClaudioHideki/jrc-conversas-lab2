# frozen_string_literal: true

class JrcContactCenter::ConfigurationAuditSnapshot
  FIELDS = {
    'JrcContactCenter::Unit' => %w[code name kind status timezone parent_unit_id],
    'JrcContactCenter::Queue' => %w[unit_id code name service_kind strategy status max_wait_seconds active_from active_until],
    'JrcContactCenter::QueueMembership' => %w[queue_id account_user_id role priority active starts_at ends_at]
  }.freeze

  def self.capture(record)
    queue = queue_for(record)
    unit = record.is_a?(JrcContactCenter::Unit) ? record : JrcContactCenter::Unit.find_by!(account_id: record.account_id, id: queue.unit_id)
    attributes = record.as_json(only: FIELDS.fetch(record.class.name))
    attributes['settings'] = record.settings.slice('issuer_company_id', 'business_unit_id') if record.is_a?(JrcContactCenter::Unit)
    if record.is_a?(JrcContactCenter::QueueMembership)
      attributes['participates'] = record.role == 'agent'
      attributes['supervises'] = record.role == 'supervisor' || record.settings['supervises'] == true
    end
    {
      'attributes' => attributes,
      'scope' => {
        'account_id' => record.account_id.to_s, 'unit_id' => unit.id.to_s, 'queue_id' => queue&.id&.to_s,
        'issuer_company_id' => unit.settings['issuer_company_id'].presence&.to_s,
        'business_unit_id' => unit.settings['business_unit_id'].presence&.to_s
      }
    }
  end

  def self.queue_for(record)
    return record if record.is_a?(JrcContactCenter::Queue)
    return unless record.is_a?(JrcContactCenter::QueueMembership)

    JrcContactCenter::Queue.find_by!(account_id: record.account_id, id: record.queue_id)
  end
  private_class_method :queue_for
end

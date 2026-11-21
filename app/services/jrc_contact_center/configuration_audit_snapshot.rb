# frozen_string_literal: true

class JrcContactCenter::ConfigurationAuditSnapshot
  UNIT_SCOPED_TYPES = %w[JrcContactCenter::AudioFolder JrcContactCenter::AudioAsset JrcContactCenter::AudioVersion
                         JrcContactCenter::AudioInspection].freeze
  ACCOUNT_SCOPED_TYPES = %w[JrcContactCenter::AccessGrant JrcContactCenter::TeamState JrcContactCenter::TeamSupervision].freeze
  FIELDS = {
    'JrcContactCenter::Unit' => %w[code name kind status timezone parent_unit_id],
    'JrcContactCenter::Queue' => %w[unit_id code name service_kind strategy status max_wait_seconds active_from active_until],
    'JrcContactCenter::QueueMembership' => %w[queue_id account_user_id role priority active starts_at ends_at],
    'JrcContactCenter::AccessGrant' => %w[account_user_id team_id eligible allowed denied],
    'JrcContactCenter::TeamState' => %w[team_id active lock_version],
    'JrcContactCenter::TeamSupervision' => %w[team_id account_user_id kind],
    'JrcContactCenter::AudioFolder' => %w[unit_id parent_id name description lock_version],
    'JrcContactCenter::AudioAsset' => %w[unit_id folder_id name description purpose lock_version],
    'JrcContactCenter::AudioVersion' => %w[unit_id audio_asset_id number source_kind content_type byte_size sha256 created_by_id],
    'JrcContactCenter::AudioInspection' => %w[unit_id audio_version_id attempt state probe_state expected_sha256 observed_sha256
                                              scanner_adapter decoder_version metadata observed_at created_by_id],
    'JrcContactCenter::RoutingRule' => %w[version rule_key kind source_value target_unit_id target_queue_id priority state starts_at ends_at]
  }.freeze

  def self.capture(record)
    return routing_snapshot(record) if record.is_a?(JrcContactCenter::RoutingRule)

    if ACCOUNT_SCOPED_TYPES.include?(record.class.name)
      return { 'attributes' => attributes_for(record), 'scope' => { 'account_id' => record.account_id.to_s } }
    end

    if UNIT_SCOPED_TYPES.include?(record.class.name)
      unit = JrcContactCenter::Unit.find_by!(account_id: record.account_id, id: record.unit_id)
      return { 'attributes' => attributes_for(record), 'scope' => scope_for(record, unit, nil) }
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

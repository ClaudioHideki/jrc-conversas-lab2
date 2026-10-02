# Reuse the existing audit store. Do not swallow audit failures on master writes.
class JrcCustomers::Audit
  def self.record!(account:, actor:, resource:, event_type:, metadata: {}, from_value: nil, to_value: nil)
    JrcCrm::AuditEvent.create!(
      account_id: account.id, actor_type: actor&.class&.name || 'System', actor_id: actor&.id,
      resource_type: resource.is_a?(JrcCustomers::Company) ? 'Company' : resource.class.name,
      resource_id: resource.id, event_type: event_type, metadata: metadata,
      from_value: from_value, to_value: to_value
    )
  end
end

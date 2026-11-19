# frozen_string_literal: true

class JrcContactCenter::ConfigurationAuditPresenter
  attr_reader :actors

  def initialize(account:, records:)
    names = account.users.where(id: records.where(user_type: 'User').reselect(:user_id)).order(:id).pluck(:id, :name)
    @actor_names = names.to_h
    @actors = names.map { |id, name| { id: id, name: name } }
  end

  def call(record)
    changes = record.audited_changes
    attributes = changes['attributes'] || role_attributes(changes)
    actor_name = @actor_names[record.user_id] if record.user_type == 'User'
    payload = {
      id: record.id, created_at: record.created_at, actor_id: record.user_id, actor_name: actor_name,
      resource_type: JrcContactCenter::ConfigurationAuditQuery.resource_key(record),
      resource_id: record.auditable_id, operation: record.action, revision: record.version,
      correlation_id: record.request_uuid, before: attributes.first, after: attributes.last,
      scopes: changes['cc_scope'], omitted_fields: changes.fetch('omitted_fields', []), result: 'recorded_locally'
    }
    if changes['manager_review'].is_a?(Hash)
      payload[:manager_review] = changes['manager_review'].slice(*JrcContactCenter::TeamRosterWithdrawalReview::AUDIT_FIELDS)
    end
    payload
  end

  private

  def role_attributes(changes)
    previous, current = changes.fetch('permissions')
    [{ 'permissions' => previous }, { 'permissions' => current }]
  end
end

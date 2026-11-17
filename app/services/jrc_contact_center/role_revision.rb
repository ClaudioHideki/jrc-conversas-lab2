# frozen_string_literal: true

# An opt-in precondition for native role clients; this token never grants access.
class JrcContactCenter::RoleRevision
  def self.token(role)
    Digest::SHA256.hexdigest(
      [role.id, role.account_id, role.name, role.description, role.permissions, role.updated_at.utc.iso8601(6)].to_json
    )
  end

  def self.check!(role, expected)
    unless expected.is_a?(String) && expected.present?
      raise JrcContactCenter::OperationError.new('role_revision_required', status: :precondition_required)
    end
    return if ActiveSupport::SecurityUtils.secure_compare(token(role), expected)

    raise JrcContactCenter::OperationError.new('stale_role_revision', status: :conflict)
  end
end

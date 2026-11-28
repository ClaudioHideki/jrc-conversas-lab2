# frozen_string_literal: true

require_relative 'owned_recording_media'

# QA only: reuse the existing exact source/nonce/host/branch/database boundary.
# Changes one explicit synthetic right and restores it without replacing any
# independent permission. Never loaded by application initialization.
module SyntheticRecordingReportAccess
  RIGHT = 'jrc_contact_center_reports'

  def self.call(account_id:, member_id:, operation:, original: nil)
    account = Account.find(account_id)
    SyntheticRecordedCallMedia.control!(account)
    raise 'Actual owned CSV database required' unless ApplicationRecord.connection.current_database == 'jrc_sd_bc_portal_concurrency_20261025_test'
    raise 'Explicit owned CSV authority action required' unless %w[grant restore].include?(operation)

    account.with_lock do
      member = account.account_users.find(member_id)
      role = member.custom_role
      raise 'Exact synthetic recording agent role required' unless member.agent? && role && role.account_id == account.id

      role.with_lock do
        proof = operation == 'grant' ? grant!(role) : restore!(role, original)
        proof.merge(source_sha: ENV.fetch('GITHUB_SHA'), account_id: account.id.to_s, member_id: member.id.to_s,
                    role_id: role.id.to_s, actor_id: member.user_id.to_s, operation: operation, synthetic: true, external_operations: false)
      end
    end
  end

  def self.grant!(role)
    original = role.permissions.dup
    raise 'CSV report right must initially be absent' if original.include?(RIGHT)

    role.update!(permissions: original + [RIGHT])
    { original_permissions: original, original_permissions_sha256: Digest::SHA256.hexdigest(original.to_json) }
  end

  def self.restore!(role, original)
    valid = original.is_a?(Array) && original.all? { |value| value.is_a?(String) }
    raise 'Exact original synthetic role permissions required' unless valid
    raise 'Preserve concurrent synthetic role changes' unless role.permissions.sort == (original + [RIGHT]).sort

    role.update!(permissions: original)
    { restored_original_permissions: true, original_permissions_sha256: Digest::SHA256.hexdigest(original.to_json) }
  end
end

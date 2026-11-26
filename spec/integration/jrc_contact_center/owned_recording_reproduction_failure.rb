# frozen_string_literal: true

require_relative 'owned_recording_media'

# Real PostgreSQL audit rejection in exactly one nonce-owned synthetic account.
# No API, service, authorization, or successful audit is substituted.
module SyntheticRecordingReproductionFailure
  def self.call(identifier, operation)
    SyntheticRecordedCallMedia.validate_environment!
    account = Account.find(identifier)
    SyntheticRecordedCallMedia.control!(account)
    raise 'Explicit owned audit fixture action required' unless %w[install remove].include?(operation)

    name = "cc_recording_reproduce_#{Integer(account.id)}"
    apply!(account, name, operation)
    { source_sha: ENV.fetch('GITHUB_SHA'), account_id: account.id, operation: operation,
      own_constraint_only: true, business_records_changed: false }
  end

  def self.apply!(account, name, operation)
    connection = ApplicationRecord.connection
    table = Audited.audit_class.table_name
    if operation == 'remove'
      connection.remove_check_constraint(table, name: name)
      return
    end
    predicate = "associated_type <> 'Account' OR associated_id <> #{Integer(account.id)} OR " \
                "comment <> 'jrc_contact_center_recording_reproduction_v1'"
    connection.add_check_constraint(table, predicate, name: name)
  end
end

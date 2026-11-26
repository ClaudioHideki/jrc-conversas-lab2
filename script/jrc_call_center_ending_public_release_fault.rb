# frozen_string_literal: true

# Remove only the test-specific failure constraint after a real rolled-back
# browser action. No cleanup of records, queues, receipts or other constraints.
require_relative '../spec/integration/jrc_contact_center/owned_public_ending_queue'

configuration = SyntheticPublicEndingQueue.configuration!
raise 'One owned account identifier required' unless ARGV.length == 1 && ARGV.first.match?(/\A[1-9][0-9]{0,18}\z/)

account_id = Integer(ARGV.first)
raise 'Account is not owned by this browser witness' unless configuration.fetch('account_ids').include?(account_id)

origin = JrcContactCenter::EndingActionOrigin.find_by!(account_id: account_id)
attempts = JrcContactCenter::EndingDestinationAttempt.where(account_id: account_id, origin: origin)
raise 'The explicit original manual action must have actually failed' unless attempts.count == 1 &&
                                                                          attempts.first.outcome&.outcome == 'failed'
raise 'Native Task must have been rolled back' if JrcProjects::Task.exists?(account_id: account_id)
raise 'No successful destination receipt may exist yet' if JrcContactCenter::EndingDestinationExecution.exists?(account_id: account_id)

name = "cc_public_ending_#{account_id}"
connection = ApplicationRecord.connection
constraints = connection.check_constraints(:jrc_contact_center_ending_destination_executions)
raise 'Expected own synthetic failure constraint missing' unless constraints.one? { |constraint| constraint.name == name }

connection.remove_check_constraint(:jrc_contact_center_ending_destination_executions, name: name)
puts({ source_sha: configuration.fetch('source_sha'), account_id: account_id,
       only_owned_synthetic_failure_removed: true, existing_data_deleted: false }.to_json)

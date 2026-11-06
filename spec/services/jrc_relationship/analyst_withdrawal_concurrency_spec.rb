require 'rails_helper'
require 'timeout'

RSpec.describe JrcRelationship::AnalystWithdrawal do
  self.use_transactional_tests = false

  it 'serializes a real separate-connection admission and retains the synthetic cohort without truncation or cleanup' do
    database = ApplicationRecord.connection.select_value('SELECT current_database()')
    raise 'Only the owned synthetic candidate database is allowed' unless Rails.env.test? && database == 'jrc_rel_v2_candidate_test'

    account = create(:account)
    account.enable_features!('jrc_customer_master', 'jrc_relationship')
    actor = create(:user, account: account, role: :administrator)
    analyst = create(:user, account: account, role: :agent)
    contact = create(:contact, account: account)
    context = JrcRelationship::Context.new(account.account_users.find_by!(user: actor))
    pid = Queue.new
    outcome = Queue.new
    worker = nil
    AccountUser.transaction do
      JrcRelationship::DistributionApproval.lock_configuration!(account.id)
      worker = Thread.new do
        ApplicationRecord.connection_pool.with_connection do |connection|
          pid << connection.select_value('SELECT pg_backend_pid()')
          JrcRelationship::Assignment.transaction do
            connection.execute("SET LOCAL lock_timeout = '5s'")
            JrcRelationship::Assignment.create!(account_id: account.id, contact_id: contact.id, owner_id: analyst.id)
          end
          outcome << :unexpected_admission
        rescue ActiveRecord::RecordInvalid => e
          outcome << e.record.errors[:owner]
        rescue StandardError => e
          outcome << { unexpected_error: e.class.name }
        end
      end
      worker_pid = Timeout.timeout(5) { pid.pop }
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
      blocked = false
      until blocked || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        blocked = ApplicationRecord.connection.select_value("SELECT cardinality(pg_blocking_pids(#{Integer(worker_pid)})) > 0")
        sleep 0.01 unless blocked
      end
      expect(blocked).to be(true)
      review = JrcRelationship::WithdrawalReadiness.new(context).call(analyst.id)
      described_class.new(context).call(analyst.id, reason: 'Synthetic concurrent handoff completed', snapshot_digest: review.fetch(:snapshot_digest))
    end
    raise 'Synthetic admission worker did not complete' unless worker.join(10)

    expect(Timeout.timeout(5) { outcome.pop }).to include('is withdrawn from Relationship; choose an eligible current owner')
    expect(JrcRelationship::Assignment.where(account: account, contact: contact)).not_to exist
    expect(account.account_users.find_by!(user: analyst).jrc_relationship_withdrawn_at).to be_present
    RSpec.configuration.reporter.message("Retained synthetic withdrawal concurrency account_id=#{account.id}; no cleanup executed")
  ensure
    worker&.join(10)
  end
end

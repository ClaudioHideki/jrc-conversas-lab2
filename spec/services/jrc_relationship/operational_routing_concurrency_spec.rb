require 'rails_helper'
require 'timeout'

RSpec.describe JrcRelationship::OperationalRouting do
  self.use_transactional_tests = false

  it 'refuses the native configuration lock without waiting on an inverted source lock, then succeeds after release' do
    expect(ActiveRecord::Base.connection.select_value('SELECT current_database()')).to eq('jrc_rel_v2_candidate_test')
    account = create(:account)
    account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    actor = create(:user, account: account, role: :administrator)
    member = account.account_users.find_by!(user: actor)
    assignment = JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account))
    action = assignment.actions.build(account: account, kind: 'health', reason: 'Synthetic contention', source_key: SecureRandom.uuid)
    ready = Queue.new
    release = Queue.new
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        JrcRelationship::Assignment.transaction do
          JrcRelationship::DistributionApproval.lock_configuration!(account.id)
          ready << true
          Timeout.timeout(15) { release.pop }
        end
      end
    end
    Timeout.timeout(10) { ready.pop }
    assignment.with_lock do
      expect { described_class.new(JrcRelationship::Context.new(member)).prepare!(action) }.to raise_error(ActiveRecord::LockWaitTimeout)
    end
    expect(JrcOperations::Queue.where(account: account)).to be_empty
    expect(assignment.actions).to be_empty
    release << true
    worker.value
    described_class.new(JrcRelationship::Context.new(member)).prepare!(action)
    action.save!
    expect(action.reload.owner_id).to eq(actor.id)
  ensure
    release << true if release
    worker&.join(20)
  end
end

# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

# Domain proof with real committed PostgreSQL. This does not prove a public
# controller, consent UI, selected terminal retry or actual worker dequeue.
RSpec.describe 'Native manual ending intent request boundary' do
  self.use_transactional_tests = false
  include_context 'with native typed ending schema evidence'

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Exclusive committed manual consent database required' unless owned
    raise 'Independent consent boundary required' if ApplicationRecord.connection.transaction_open?

    previous = JrcContactCenter::EndingDestinationJob._test_adapter
    JrcContactCenter::EndingDestinationJob.enable_test_adapter(ActiveJob::QueueAdapters::TestAdapter.new)
    example.run
  ensure
    JrcContactCenter::EndingDestinationJob.enable_test_adapter(previous)
  end

  def native_review
    metadata = typed_context
    { 'confirmed' => true, 'expected_readiness_id' => metadata.fetch('readiness_id').to_s,
      'expected_version_id' => metadata.fetch('version_id').to_s, 'expected_rule_sha256' => metadata.fetch('rule_sha256') }
  end

  def command(review: native_review, key: typed_key, caller: member)
    JrcContactCenter::EndingActions::RequestManualDestination.new(
      account: account, member: caller, qualification_id: typed_origin.source_qualification_id,
      origin_id: typed_origin.id, rule_code: 'SYNTHETIC_ORIGIN_RULE', destination_kind: 'project_task', request_key: key, review: review
    )
  end

  def intent_counts
    [JrcContactCenter::EndingDestinationConsent.where(account: account).count,
     JrcContactCenter::EndingDestinationAttempt.where(account: account).count, JrcProjects::Task.where(account: account).count]
  end

  it 'records one separate explicit original-agent action consent and durable intent without completing or executing a native target' do
    qualification = JrcContactCenter::Qualification.find(typed_origin.source_qualification_id)
    previous = qualification.completed_at
    row = command.call
    expect(row.consent.actor_account_user_id).to eq(member.id)
    expect(row.consent.request_key).to eq(row.request_key)
    expect(row.request_key).to eq(typed_key)
    expect(intent_counts).to eq([1, 1, 0])
    expect(qualification.reload.completed_at).to eq(previous)
    expect(row.outcome).to be_nil
    expect(row.retry_of_id).to be_nil
  end

  context 'when classification is confirmed while ACW is still open' do
    let(:typed_version) { publish_typed_schema_definition('timing' => 'call_end') }
    let(:typed_origin) do
      original = origin
      JrcContactCenter::ConfirmEndingReason.new(account: account, member: member).call(
        qualification, attributes: { reason_code: 'SYNTHETIC_ORIGIN_REASON' },
        expected_revision: JrcContactCenter::QualificationDraftRevision.token(qualification), request_key: SecureRandom.uuid
      )
      original.reload
    end

    it 'records separate action consent and intent without finishing the open ACW or executing a destination' do
      original = typed_origin
      expect(qualification.reload.completed_at).to be_nil
      expect(JrcContactCenter::EndingReasonConfirmation.where(account: account, source_qualification_id: qualification.id).count).to eq(1)
      expect(intent_counts).to eq([0, 0, 0])

      result = command.call

      expect([result.origin_id, result.consent.actor_account_user_id]).to eq([original.id, member.id])
      expect(intent_counts).to eq([1, 1, 0])
      expect(qualification.reload.completed_at).to be_nil
      expect(result.outcome).to be_nil
    end
  end

  it 'reviews the exact origin version when an unchanged rule legitimately reuses an earlier prospective readiness' do
    ready = typed_readiness
    publish_typed_schema_definition
    row = typed_origin
    expect(row.version_id).not_to eq(ready.version_id)
    result = command.call
    expect(result.version_id).to eq(row.version_id)
    expect(result.readiness_id).to eq(ready.id)
    expect(intent_counts).to eq([1, 1, 0])
  end

  it 'reuses the same reviewed root after an uncertain response without replacing its consent or intent' do
    first = command.call
    second = command.call
    expect([second.id, second.consent_id]).to eq([first.id, first.consent_id])
    expect(intent_counts).to eq([1, 1, 0])
  end

  it 'does not retarget a reviewed existing root to a later arming receipt of the same unchanged rule' do
    review = native_review
    first = command(review: review).call
    JrcServiceDesk::NativeExecutionContext.with(account: account, account_user: member, user: actor) do
      account.with_lock do
        JrcContactCenter::EndingActionReadiness.create!(account: account, version: typed_version, actor_account_user_id: member.id,
                                                      rule_code: 'SYNTHETIC_ORIGIN_RULE', request_key: SecureRandom.uuid)
      end
    end
    repeated = command(review: review).call
    expect([repeated.id, repeated.readiness_id, repeated.consent_id]).to eq([first.id, first.readiness_id, first.consent_id])
    expect(intent_counts).to eq([1, 1, 0])
  end

  it 'does not interpret a second request UUID as a second root action or leave an orphan consent' do
    first = command.call
    expect { command(key: SecureRandom.uuid).call }.to raise_error(JrcContactCenter::OperationError) do |error|
      expect(error.code).to eq('ending_attempt_request_conflict')
    end
    expect(intent_counts).to eq([1, 1, 0])
    expect(first.reload.request_key).to eq(typed_key)
  end

  it 'rejects a classification-like false confirmation before recording separate action consent' do
    expect { command(review: native_review.merge('confirmed' => false)).call }.to raise_error(JrcContactCenter::OperationError) do |error|
      expect(error.code).to eq('invalid_ending_pending_review')
    end
    expect(intent_counts).to eq([0, 0, 0])
  end

  it 'rejects a changed reviewed rule hash without creating consent or executing a destination' do
    changed_review = native_review.merge('expected_rule_sha256' => '0' * 64)
    expect { command(review: changed_review).call }.to raise_error(JrcContactCenter::OperationError) do |error|
      expect(error.code).to eq('ending_pending_review_changed')
    end
    expect(intent_counts).to eq([0, 0, 0])
  end

  it 'does not accept caller actor or account fields as action authority' do
    review = native_review.merge('account_id' => account.id.to_s, 'actor_account_user_id' => member.id.to_s)
    expect { command(review: review).call }.to raise_error(JrcContactCenter::OperationError) do |error|
      expect(error.code).to eq('invalid_ending_pending_review')
    end
    expect(intent_counts).to eq([0, 0, 0])
  end

  it 'does not replace the original agent by another actual account administrator with audit coverage' do
    typed_origin
    observer = create(:user, :contact_center_eligible, account: account, role: :administrator)
    observer_member = account.account_users.find_by!(user: observer)
    JrcCrm::UserBusinessUnit.create!(account: account, user: observer, scope: 'GROUP', active: true, structure_managed: true)
    expect { command(caller: observer_member).call }.to raise_error(Pundit::NotAuthorizedError)
    expect(intent_counts).to eq([0, 0, 0])
  end

  it 'does not create an automatic terminal retry when a previous consent response is replayed after failure' do
    first = command.call
    JrcContactCenter::EndingDestinationOutcome.create!(account: account, attempt: first, outcome: 'failed', result_code: 'destination_failure')
    repeated = command.call
    expect(repeated.id).to eq(first.id)
    expect(repeated.outcome.outcome).to eq('failed')
    expect(intent_counts).to eq([1, 1, 0])
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: account).where.not(retry_of_id: nil)).to be_empty
  end

  it 'keeps a previously pending root blocked after deactivation and later reactivation without minting fresh consent' do
    first = command.call
    publish_typed_schema_definition('active' => false)
    publish_typed_schema_definition('active' => true)
    expect { command.call }.to raise_error(JrcContactCenter::OperationError) do |error|
      expect(error.code).to eq('ending_action_pending_permanently_blocked')
    end
    expect(intent_counts).to eq([1, 1, 0])
    expect(first.reload.outcome).to be_nil
  end

  it 'serializes duplicate consent requests on two actual PostgreSQL backends into one original-agent intent' do
    review = native_review
    source = typed_origin
    readiness = typed_readiness
    key = typed_key
    account_id = account.id
    member_id = member.id
    jobs = Queue.new
    start = Queue.new
    threads = 2.times.map do
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do |connection|
          connection.execute("SET lock_timeout = '5s'")
          jobs << connection.select_value('SELECT pg_backend_pid()')
          Timeout.timeout(10) { start.pop }
          JrcContactCenter::EndingActions::RequestManualDestination.new(account: Account.find(account_id), member: AccountUser.find(member_id),
                              qualification_id: source.source_qualification_id, origin_id: source.id,
                              rule_code: readiness.rule_code, destination_kind: 'project_task', request_key: key, review: review).call.id
        ensure
          connection.execute('RESET lock_timeout')
        end
      end
    end
    pids = Timeout.timeout(10) { 2.times.map { jobs.pop } }
    expect(pids.uniq.length).to eq(2)
    2.times { start << true }
    Timeout.timeout(20) { threads.each(&:join) }
    expect(threads.map(&:value).uniq.length).to eq(1)
    expect(intent_counts).to eq([1, 1, 0])
  end
end

require 'rails_helper'
require 'timeout'

# Prepared domain cases using committed native PostgreSQL. Technical failed
# outcomes below exercise retry admission, not a fabricated operational failure.
RSpec.describe JrcContactCenter::EndingActions::RequestDestinationRetry do
  self.use_transactional_tests = false
  include_context 'with native typed ending schema evidence'
  include_context 'with native ending attempt operators'

  let(:operator) { attempt_operator }
  let(:typed_mode) { 'automatic' }
  let(:typed_origin) { completed_attempt_source(operator) }
  let(:retry_key) { SecureRandom.uuid }
  let(:previous) do
    row = typed_attempt
    JrcContactCenter::EndingDestinationOutcome.create!(account: account, attempt: row, outcome: 'failed', result_code: 'destination_failure')
    row
  end

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Exclusive committed selected retry database required' unless owned && !ApplicationRecord.connection.transaction_open?

    job = JrcContactCenter::EndingDestinationJob
    previous_adapter = job._test_adapter
    job.enable_test_adapter(ActiveJob::QueueAdapters::TestAdapter.new)
    example.run
  ensure
    job&.enable_test_adapter(previous_adapter)
  end

  def retry_review(row)
    { 'confirmed' => true, 'expected_readiness_id' => row.readiness_id.to_s,
      'expected_request_id' => row.request_key, 'expected_version_id' => row.version_id.to_s,
      'expected_rule_sha256' => row.rule_sha256 }
  end

  def retry_command(row = previous, key: retry_key, caller: operator, review: retry_review(row))
    described_class.new(account: account, member: caller, qualification_id: typed_origin.source_qualification_id,
                        attempt_id: row.id, request_key: key, review: review)
  end

  def retry_counts
    [JrcContactCenter::EndingDestinationAttempt.where(account: account).count,
     JrcContactCenter::EndingDestinationConsent.where(account: account).count,
     JrcProjects::Task.where(account: account).count,
     JrcContactCenter::EndingDestinationExecution.where(account: account).count]
  end

  it 'records only the selected original-agent retry and preserves the original native effect key' do
    row = previous
    result = retry_command(row).call
    expect(operator.administrator?).to be false
    expect(result).to have_attributes(retry_of_id: row.id, effect_key: row.effect_key,
                                     actor_account_user_id: operator.id, retry_requested_by_account_user_id: operator.id,
                                     readiness_id: row.readiness_id, operation: row.operation)
    expect(result.request_key).to eq(retry_key)
    expect(result.outcome).to be_nil
    expect(row.reload.outcome.outcome).to eq('failed')
    expect(retry_counts).to eq([2, 0, 0, 0])
  end

  it 'replays the same new retry request without another child or native effect' do
    first = retry_command.call
    second = retry_command.call
    expect([second.id, second.request_key, second.effect_key]).to eq([first.id, first.request_key, first.effect_key])
    expect(retry_counts).to eq([2, 0, 0, 0])
  end

  it 'does not reinterpret another request UUID as a second child while the reviewed retry is pending' do
    retry_command.call
    expect { retry_command(key: SecureRandom.uuid).call }.to raise_error(JrcContactCenter::OperationError) do |error|
      expect(error.code).to eq('ending_attempt_request_conflict')
    end
    expect(retry_counts).to eq([2, 0, 0, 0])
  end

  it 'revalidates current original-agent native Project rights before recording or delivering a retry' do
    previous
    JrcProjects::ProjectMember.where(account: account, user_id: operator.user_id).sole.update!(role: 'viewer')
    expect { retry_command.call }.to raise_error(Pundit::NotAuthorizedError)
    expect(retry_counts).to eq([1, 0, 0, 0])
  end

  it 'does not use a different administrator as the original agent or borrow their native Project authority' do
    previous
    expect { retry_command(caller: member).call }.to raise_error(Pundit::NotAuthorizedError)
    expect(retry_counts).to eq([1, 0, 0, 0])
  end

  it 'keeps an old unsuccessful destination permanently blocked after deactivation and reactivation' do
    previous
    publish_typed_schema_definition('active' => false)
    publish_typed_schema_definition('active' => true)
    expect { retry_command.call }.to raise_error(JrcContactCenter::OperationError) do |error|
      expect(error.code).to eq('ending_action_pending_permanently_blocked')
    end
    expect(retry_counts).to eq([1, 0, 0, 0])
  end

  it 'rejects an altered reviewed predecessor hash without replacing its immutable outcome' do
    row = previous
    review = retry_review(row).merge('expected_rule_sha256' => '0' * 64)
    expect { retry_command(row, review: review).call }.to raise_error(JrcContactCenter::OperationError) do |error|
      expect(error.code).to eq('ending_pending_review_changed')
    end
    expect(row.reload.outcome.outcome).to eq('failed')
    expect(retry_counts).to eq([1, 0, 0, 0])
  end

  it 'does not treat a still-pending attempt as a terminal failure to be replaced' do
    pending = typed_attempt
    expect { retry_command(pending).call }.to raise_error(JrcContactCenter::OperationError) do |error|
      expect(error.code).to eq('ending_pending_review_changed')
    end
    expect(retry_counts).to eq([1, 0, 0, 0])
  end

  it 'preserves a real successful result instead of creating a retry of a completed destination' do
    row = typed_attempt
    result = JrcContactCenter::EndingActions::ExecuteDestinationAttempt.new(account: account, attempt_id: row.id).call
    expect(result.outcome).to eq('succeeded')
    expect { retry_command(row).call }.to raise_error(JrcContactCenter::OperationError) do |error|
      expect(error.code).to eq('ending_pending_review_changed')
    end
    expect(retry_counts).to eq([1, 0, 1, 1])
  end

  it 'does not accept caller-selected actor or account fields as additional retry authority' do
    row = previous
    review = retry_review(row).merge('actor_account_user_id' => member.id.to_s)
    expect { retry_command(row, review: review).call }.to raise_error(JrcContactCenter::OperationError) do |error|
      expect(error.code).to eq('invalid_ending_pending_review')
    end
    expect(retry_counts).to eq([1, 0, 0, 0])
  end

  it 'serializes the same selected retry on two real PostgreSQL backends into a single child' do
    row = previous
    input = [account.id, operator.id, typed_origin.source_qualification_id, row.id, retry_key, retry_review(row)]
    ready = Queue.new
    start = Queue.new
    threads = 2.times.map do
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do |connection|
          connection.execute("SET lock_timeout = '5s'")
          ready << connection.raw_connection.backend_pid
          Timeout.timeout(10) { start.pop }
          described_class.new(account: Account.find(input[0]), member: AccountUser.find(input[1]), qualification_id: input[2],
                              attempt_id: input[3], request_key: input[4], review: input[5]).call.id
        ensure
          connection.execute('RESET lock_timeout')
        end
      end
    end
    pids = Timeout.timeout(10) { 2.times.map { ready.pop } }
    expect(pids.uniq.length).to eq(2)
    2.times { start << true }
    Timeout.timeout(20) { threads.each(&:join) }
    expect(threads.map(&:value).uniq.length).to eq(1)
    expect(retry_counts).to eq([2, 0, 0, 0])
  end

  context 'when the pinned mode requires separate original-agent confirmation' do
    let(:typed_mode) { 'agent_confirmation' }
    let(:previous) do
      consent = typed_consent(actor_member_id: operator.id)
      row = typed_attempt(consent: consent)
      JrcContactCenter::EndingDestinationOutcome.create!(account: account, attempt: row, outcome: 'failed', result_code: 'destination_failure')
      row
    end

    it 'records a new immutable retry consent while preserving the original reviewed consent and effect key' do
      row = previous
      original_consent = row.consent_id
      result = retry_command(row).call
      expect(result.consent_id).not_to eq(original_consent)
      expect(result.consent).to have_attributes(actor_account_user_id: operator.id, request_key: retry_key)
      expect(result.effect_key).to eq(row.effect_key)
      expect(row.reload.consent_id).to eq(original_consent)
      expect(retry_command(row).call.id).to eq(result.id)
      expect(retry_counts).to eq([2, 2, 0, 0])
    end
  end
end

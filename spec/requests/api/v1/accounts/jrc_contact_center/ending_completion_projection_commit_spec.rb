# frozen_string_literal: true

require 'rails_helper'

# Actual committed HTTP/PG boundaries. The owned test adapter measures admission;
# the separate four-mode Chrome/Sidekiq flow proves real dequeue and effects.
RSpec.describe 'Native ending dispatch survives the authenticated completion projection', type: :request do
  self.use_transactional_tests = false
  include_context 'with native ending execution original evidence'

  let(:headers) { actor.create_new_auth_token }
  let(:job) { JrcContactCenter::EndingActionsJob }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/qualifications/#{qualification.id}" }
  let(:completion) { { reason_code: 'SYNTHETIC_ORIGIN_REASON', outcome_code: 'completed' } }
  let(:baseline) { job.queue_adapter.enqueued_jobs.length }

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned committed completion projection database required' unless owned && !ApplicationRecord.connection.transaction_open?

    previous = job._test_adapter
    job.enable_test_adapter(ActiveJob::QueueAdapters::TestAdapter.new)
    example.run
  ensure
    job&.enable_test_adapter(previous)
  end

  before do
    origin
    JrcContactCenter::ConfirmEndingReason.new(account: account, member: member).call(
      qualification, attributes: { reason_code: 'SYNTHETIC_ORIGIN_REASON' },
                     expected_revision: JrcContactCenter::QualificationDraftRevision.token(qualification), request_key: SecureRandom.uuid
    )
    baseline
  end

  def complete_and_project
    row = JrcContactCenter::QualificationManager.new(account: account, member: member).complete!(qualification, completion)
    payload = JrcContactCenter::QualificationProjection.new(account: account, member: member).call(row)
    expect(payload.fetch('completed_at')).to be_present
    expect(row.saved_change_to_completed_at?).to be(true)
    row
  end

  def expect_one_new_committed_job
    added = job.queue_adapter.enqueued_jobs.drop(baseline)
    expect(added).to contain_exactly(include(job: job, args: [account.id, qualification.id]))
  end

  it 'enqueues exactly once after the real completion HTTP response and does not enqueue a replay' do
    patch endpoint, headers: headers, params: { qualification: completion }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item').fetch('completed_at')).to be_present
    expect_one_new_committed_job
    expect(JrcContactCenter::EndingActionCompletion.where(account: account, origin: origin).count).to eq(1)
    patch endpoint, headers: headers, params: { qualification: completion }, as: :json
    expect(response).to have_http_status(:ok)
    expect_one_new_committed_job
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'retains native completion admission through a locked projection while waiting for the actual outer commit' do
    JrcContactCenter::AuthorityTransaction.call(account: account, member: member) do
      row = complete_and_project
      expect(row.completed_at).to be_present
      expect(job.queue_adapter.enqueued_jobs.length).to eq(baseline)
    end
    expect_one_new_committed_job
    expect(qualification.reload.completed_at).to be_present
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'does not enqueue or retain a completion after the outer completion and projection transaction rolls back' do
    JrcContactCenter::AuthorityTransaction.call(account: account, member: member) do
      complete_and_project
      expect(job.queue_adapter.enqueued_jobs.length).to eq(baseline)
      raise ActiveRecord::Rollback
    end
    expect(qualification.reload.completed_at).to be_nil
    expect(JrcContactCenter::EndingActionCompletion.where(account: account, origin: origin)).to be_empty
    expect(job.queue_adapter.enqueued_jobs.length).to eq(baseline)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'does not interpret repeated pending attendance projections as completion or dispatch authorization' do
    2.times do
      payload = JrcContactCenter::QualificationProjection.new(account: account, member: member).call(qualification)
      expect(payload.fetch('completed_at')).to be_nil
    end
    expect(qualification.reload.completed_at).to be_nil
    expect(JrcContactCenter::EndingActionCompletion.where(account: account, origin: origin)).to be_empty
    expect(job.queue_adapter.enqueued_jobs.length).to eq(baseline)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end
end

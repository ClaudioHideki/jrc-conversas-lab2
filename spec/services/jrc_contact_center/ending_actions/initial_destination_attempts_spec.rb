# frozen_string_literal: true

require 'rails_helper'

# Native source-event admission preparation; not a public editor or browser proof.
# Committed source rows and all SQL guards stay real. Only this job's delivery
# adapter is local to an example; owned-worker dequeue has its independent probe.
RSpec.describe JrcContactCenter::EndingActions::InitialDestinationAttempts do
  self.use_transactional_tests = false

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned committed original-event database required' unless owned && !ApplicationRecord.connection.transaction_open?

    job = JrcContactCenter::EndingDestinationJob
    previous = job._test_adapter
    job.enable_test_adapter(ActiveJob::QueueAdapters::TestAdapter.new)
    example.run
  ensure
    job.enable_test_adapter(previous) if job
  end

  include_context 'with native typed ending schema evidence'
  include_context 'with native ending attempt operators'

  let(:typed_mode) { 'automatic' }
  let(:qualification_id) { typed_origin.source_qualification_id }
  let(:command) { described_class.new(account: account, qualification_id: qualification_id) }

  it 'records the actual pinned destination once and redelivers only that durable unfinished attempt' do
    rows = command.call
    expect(rows.length).to eq(1)
    expect(rows.first).to have_attributes(origin_id: typed_origin.id, readiness_id: typed_readiness.id,
                                         actor_account_user_id: member.id, destination_kind: 'project_task')
    expect(command.call.map(&:id)).to eq(rows.map(&:id))
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: account).count).to eq(1)
    expect(JrcContactCenter::EndingDestinationJob.queue_adapter.enqueued_jobs.length).to eq(2)
    expect(JrcProjects::Task.where(account: account)).to be_empty
    expect(JrcContactCenter::EndingDestinationExecution.where(account: account)).to be_empty
  end

  it 'records independent destinations from one exact native origin without creating either business record' do
    project = typed_version.definition.fetch('entries').first.fetch('actions').first
    version = publish_typed_schema_definition('actions' => [project, { 'kind' => 'crm', 'parameters' => {} }])
    ready = JrcContactCenter::EndingActionReadiness.create!(account: account, version: version, actor_account_user_id: member.id,
                                                          rule_code: 'SYNTHETIC_ORIGIN_RULE', request_key: SecureRandom.uuid)
    original = completed_attempt_source(member)
    rows = described_class.new(account: account, qualification_id: original.source_qualification_id).call
    expect(rows.map(&:destination_kind).sort).to eq(%w[crm project_task])
    expect(rows.map(&:origin_id).uniq).to eq([original.id])
    expect(rows.map(&:readiness_id).uniq).to eq([ready.id])
    expect(account.jrc_crm_leads).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
    expect(JrcContactCenter::EndingDestinationOutcome.where(account: account)).to be_empty
  end

  it 'does not borrow another accounts qualification or create a surrogate source' do
    typed_origin
    foreign = create(:account)
    result = described_class.new(account: foreign, qualification_id: qualification_id).call
    expect(result).to eq([])
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: foreign)).to be_empty
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: account)).to be_empty
  end

  it 'revalidates the original agent eligibility before admitting work from an earlier committed source' do
    typed_origin
    grant = JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member)
    grant.update!(eligible: false)

    expect(command.call).to eq([])
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: account)).to be_empty
    expect(JrcContactCenter::EndingDestinationJob.queue_adapter.enqueued_jobs).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'routes the real committed qualification job through the typed producer without executing a target in the source job' do
    original = typed_origin
    result = JrcContactCenter::EndingActionsJob.perform_now(account.id, original.source_qualification_id)

    expect(result).to eq(1)
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: account).count).to eq(1)
    expect(JrcContactCenter::EndingActionAttempt.where(account: account)).to be_empty
    expect(JrcContactCenter::EndingDestinationJob.queue_adapter.enqueued_jobs.length).to eq(1)
    expect(JrcContactCenter::EndingDestinationExecution.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'preserves a permanently blocked predecessor after deactivation and never converts its replay into a retry' do
    previous = command.call.sole
    publish_typed_schema_definition('active' => false)
    outcome = JrcContactCenter::EndingActions::ExecuteDestinationAttempt.new(account: account, attempt_id: previous.id).call
    publish_typed_schema_definition('active' => true)
    expect(outcome).to have_attributes(outcome: 'blocked', result_code: 'deactivated')
    expect(command.call.map(&:id)).to eq([previous.id])
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: account).count).to eq(1)
    expect(JrcContactCenter::EndingDestinationJob.queue_adapter.enqueued_jobs.length).to eq(1)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  context 'with explicit agent confirmation' do
    let(:typed_mode) { 'agent_confirmation' }

    it 'does not substitute reason confirmation or completed ACW for manual destination consent' do
      expect(command.call).to eq([])
      expect(JrcContactCenter::EndingDestinationAttempt.where(account: account)).to be_empty
      expect(JrcContactCenter::EndingDestinationConsent.where(account: account)).to be_empty
      expect(JrcContactCenter::EndingDestinationJob.queue_adapter.enqueued_jobs).to be_empty
    end
  end

  context 'with the legacy grammar' do
    let(:typed_schema_marker) { false }

    it 'leaves schema1 exclusively on its existing producer without admitting a typed duplicate' do
      expect(command.call).to eq([])
      expect(JrcContactCenter::EndingDestinationAttempt.where(account: account)).to be_empty
      expect(JrcContactCenter::EndingDestinationJob.queue_adapter.enqueued_jobs).to be_empty
    end
  end

  context 'before actual ACW completion' do
    let(:qualification_id) { origin.source_qualification_id }

    it 'does not run an ACW-completed rule merely because its telephone call already ended' do
      expect(command.call).to eq([])
      expect(JrcContactCenter::EndingActionCompletion.where(account: account)).to be_empty
      expect(JrcContactCenter::EndingDestinationAttempt.where(account: account)).to be_empty
      expect(JrcContactCenter::EndingDestinationJob.queue_adapter.enqueued_jobs).to be_empty
    end
  end

  context 'with a call-end rule before explicit classification' do
    let(:typed_version) { publish_typed_schema_definition('timing' => 'call_end') }
    let(:qualification_id) { origin.source_qualification_id }

    it 'does not infer confirmation from a terminated call or start a destination effect' do
      expect(command.call).to eq([])
      expect(JrcContactCenter::EndingReasonConfirmation.where(account: account)).to be_empty
      expect(JrcContactCenter::EndingDestinationAttempt.where(account: account)).to be_empty
      expect(JrcProjects::Task.where(account: account)).to be_empty
    end
  end
end

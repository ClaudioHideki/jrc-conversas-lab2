# frozen_string_literal: true

require 'rails_helper'

# Prepared committed PostgreSQL cases, not an executed native approval.
# This is an internal intent command; no public configuration or dispatch API.
RSpec.describe JrcContactCenter::EndingActions::QueueDestinationAttempt do
  self.use_transactional_tests = false

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned disposable typed queue database required' unless owned && !ApplicationRecord.connection.transaction_open?

    # This probe proves metadata, not a broker dequeue. Its native callback
    # receives a fresh per-example test adapter, never another test's Redis queue.
    job = JrcContactCenter::EndingDestinationJob
    previous_test_adapter = job._test_adapter
    job.enable_test_adapter(ActiveJob::QueueAdapters::TestAdapter.new)
    example.run
  ensure
    job&.enable_test_adapter(previous_test_adapter)
  end

  include_context 'with native typed ending schema evidence'
  include_context 'with native ending attempt operators'

  let(:typed_mode) { 'automatic' }
  let(:command) do
    described_class.new(account: account, origin_id: typed_origin.id, rule_code: 'SYNTHETIC_ORIGIN_RULE',
                        destination_kind: 'project_task', request_key: typed_key)
  end

  before { typed_origin }

  it 'records one automatic intent for the actual original actor without creating a task or success receipt' do
    row = command.call
    expect(row).to have_attributes(account_id: account.id, origin_id: typed_origin.id, actor_account_user_id: member.id,
                                   actor_user_id: actor.id, readiness_id: typed_readiness.id, destination_kind: 'project_task')
    expect(row.effect_key).to eq(typed_key)
    expect(row.consent_id).to be_nil
    expect(JrcContactCenter::EndingDestinationJob.queue_adapter.enqueued_jobs.length).to eq(1)
    expect(row.outcome).to be_nil
    expect(JrcProjects::Task.where(account: account)).to be_empty
    expect(JrcContactCenter::EndingDestinationExecution.where(account: account)).to be_empty
  end

  it 'acknowledges exactly repeated admission without adding an attempt or native effect' do
    previous = command.call
    expect(command.call.attributes).to eq(previous.attributes)
    expect(JrcContactCenter::EndingDestinationJob.queue_adapter.enqueued_jobs.length).to eq(1)
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: account).count).to eq(1)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'selects only an explicitly configured CRM intent without manufacturing a lead or destination unit' do
    version = publish_typed_schema_definition('actions' => [{ 'kind' => 'crm', 'parameters' => {} }])
    ready = JrcContactCenter::EndingActionReadiness.create!(account: account, version: version, actor_account_user_id: member.id,
                                                            rule_code: 'SYNTHETIC_ORIGIN_RULE', request_key: SecureRandom.uuid).reload
    # Use the actual original fixture's native source; this changed definition
    # needs a new attendance, never a silent rewrite of its prior immutable origin.
    original = completed_attempt_source(member)
    crm_command = described_class.new(account: account, origin_id: original.id, rule_code: 'SYNTHETIC_ORIGIN_RULE',
                                      destination_kind: 'crm', request_key: SecureRandom.uuid)
    row = crm_command.call
    expect(row).to have_attributes(destination_kind: 'crm', operation: 'create_lead', readiness_id: ready.id,
                                   actor_account_user_id: member.id)
    expect(account.jrc_crm_leads).to be_empty
    expect(JrcContactCenter::EndingDestinationExecution.where(account: account)).to be_empty
  end

  it 'refuses an action that is absent from the pinned rule' do
    missing = described_class.new(account: account, origin_id: typed_origin.id, rule_code: 'SYNTHETIC_ORIGIN_RULE',
                                  destination_kind: 'service_desk', request_key: typed_key)
    expect { missing.call }.to raise_error(JrcContactCenter::OperationError, 'ending_action_destination_unavailable')
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: account)).to be_empty
  end

  it 'rechecks source rights withdrawn after the attendance was completed' do
    account.disable_features!('jrc_contact_center')
    expect { command.call }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'does not revive a prior origin after deactivation followed by reactivation' do
    publish_typed_schema_definition('active' => false)
    publish_typed_schema_definition('active' => true)
    expect { command.call }.to raise_error(JrcContactCenter::OperationError, 'ending_action_pending_permanently_blocked')
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'does not borrow a valid origin through another account' do
    foreign = create(:account)
    changed = described_class.new(account: foreign, origin_id: typed_origin.id, rule_code: 'SYNTHETIC_ORIGIN_RULE',
                                  destination_kind: 'project_task', request_key: typed_key)
    expect { changed.call }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: foreign)).to be_empty
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: account)).to be_empty
  end

  it 'requires its own source-authorized transaction rather than a surrounding caller transaction' do
    expect do
      ApplicationRecord.transaction { command.call }
    end.to raise_error(JrcContactCenter::OperationError, 'ending_execution_requires_independent_transaction')
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: account)).to be_empty
  end

  context 'with an explicitly manual rule' do
    let(:typed_mode) { 'agent_confirmation' }

    it 'never substitutes classification or completed ACW for explicit manual action consent' do
      expect { command.call }.to raise_error(JrcContactCenter::OperationError, 'ending_action_requires_agent_confirmation')
      expect(JrcContactCenter::EndingDestinationAttempt.where(account: account)).to be_empty
      expect(JrcContactCenter::EndingDestinationConsent.where(account: account)).to be_empty
    end
  end

  context 'with the preserved legacy grammar' do
    let(:typed_schema_marker) { false }

    it 'keeps schema1 admission on its native Project-only path' do
      expect { command.call }.to raise_error(JrcContactCenter::OperationError, 'ending_action_destination_unavailable')
      expect(JrcContactCenter::EndingDestinationAttempt.where(account: account)).to be_empty
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

# Real native Task commands and PostgreSQL integrity/rollback cases, prepared
# but not executed. Executor API, current-role and real-contention proofs are separate.
RSpec.describe JrcContactCenter::EndingDestinationAttempt, type: :model do
  include_context 'with native typed ending schema evidence'

  it 'preserves the root effect identity on an explicitly reviewed retry of an unsuccessful attempt' do
    first = failed_typed_attempt
    next_key = SecureRandom.uuid
    consent = typed_consent(key: next_key)
    retry_row = typed_attempt(consent: consent, key: next_key, retry_of: first, retry_requested_by_account_user_id: member.id)
    expect(retry_row.effect_key).to eq(first.effect_key)
    expect(retry_row.request_key).not_to eq(first.request_key)
    expect(retry_row.retry_of_id).to eq(first.id)
    expect(first.reload.outcome.outcome).to eq('failed')
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'refuses retry ancestry without an original-agent review identity' do
    first = failed_typed_attempt
    next_key = SecureRandom.uuid
    consent = typed_consent(key: next_key)
    expect { refused_typed_schema_write { typed_attempt(consent: consent, key: next_key, retry_of: first) } }
      .to raise_error(ActiveRecord::StatementInvalid, /exact unsuccessful predecessor and original-agent review/)
    expect(described_class.where(account: account).count).to eq(1)
  end

  it 'refuses another member as the actor of a selected retry' do
    first = failed_typed_attempt
    foreign_actor = create(:user, :contact_center_eligible, account: account, role: :administrator)
    foreign_member = account.account_users.find_by!(user: foreign_actor)
    next_key = SecureRandom.uuid
    consent = typed_consent(key: next_key)
    expect do
      refused_typed_schema_write do
        typed_attempt(consent: consent, key: next_key, retry_of: first, retry_requested_by_account_user_id: foreign_member.id)
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /exact unsuccessful predecessor and original-agent review/)
  end

  it 'refuses another attempt while the preceding explicit retry is still unfinished' do
    first = failed_typed_attempt
    next_key = SecureRandom.uuid
    next_consent = typed_consent(key: next_key)
    second = typed_attempt(consent: next_consent, key: next_key, retry_of: first, retry_requested_by_account_user_id: member.id)
    last_key = SecureRandom.uuid
    last_consent = typed_consent(key: last_key)
    expect do
      refused_typed_schema_write do
        typed_attempt(consent: last_consent, key: last_key, retry_of: first, retry_requested_by_account_user_id: member.id)
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /exact unsuccessful predecessor and original-agent review/)
    expect(second.reload.outcome).to be_nil
    expect(described_class.where(account: account).count).to eq(2)
  end

  it 'does not release an old unsuccessful action after disabling and reactivating its original rule' do
    first = failed_typed_attempt
    publish_typed_schema_definition('active' => false)
    publish_typed_schema_definition('active' => true)
    next_key = SecureRandom.uuid
    expect { refused_typed_schema_write { typed_consent(key: next_key) } }
      .to raise_error(ActiveRecord::StatementInvalid, /permanently blocked by deactivation/)
    expect(first.reload.outcome.outcome).to eq('failed')
    expect(described_class.where(account: account).count).to eq(1)
  end

  it 'does not give an unrelated first attempt a forged effect key or retry actor' do
    consent = typed_consent
    expect { refused_typed_schema_write { typed_attempt(consent: consent, effect_key: SecureRandom.uuid) } }
      .to raise_error(ActiveRecord::StatementInvalid, /attempt evidence is server generated/)
    expect { refused_typed_schema_write { typed_attempt(consent: consent, retry_requested_by_account_user_id: member.id) } }
      .to raise_error(ActiveRecord::StatementInvalid, /first attempt cannot invent retry ancestry/)
  end

  it 'records a real native Task success with typed identity generated from the exact original attempt' do
    attempt = typed_attempt(consent: typed_consent)
    task = typed_native_task(attempt)
    result = JrcContactCenter::EndingDestinationExecution.create!(account: account, attempt: attempt, target_id: task.id).reload
    expect(result.attributes).to include('origin_id' => typed_origin.id, 'version_id' => typed_version.id,
                                        'actor_account_user_id' => member.id, 'actor_user_id' => actor.id,
                                        'destination_kind' => 'project_task', 'operation' => 'create_task',
                                        'target_type' => 'JrcProjects::Task', 'effect_key' => attempt.effect_key)
    expect(JrcProjects::AuditEvent.where(account: account, action: 'projects.task.created')).not_to be_empty
    expect(result.integrity_sha256).to match(/\A[0-9a-f]{64}\z/)
  end

  it 'links the successful outcome to that exact typed execution without changing its attempt' do
    attempt = typed_attempt(consent: typed_consent)
    before = attempt.attributes
    task = typed_native_task(attempt)
    execution = JrcContactCenter::EndingDestinationExecution.create!(account: account, attempt: attempt, target_id: task.id).reload
    result = JrcContactCenter::EndingDestinationOutcome.create!(account: account, attempt: attempt, execution: execution,
                                                               outcome: 'succeeded', result_code: 'completed').reload
    expect(result.execution_id).to eq(execution.id)
    expect(attempt.reload.attributes).to eq(before)
    expect(JrcProjects::Task.where(account: account).count).to eq(1)
  end

  it 'refuses a real native Task whose audit belongs to a different effect identity' do
    attempt = typed_attempt(consent: typed_consent)
    task = typed_native_task(attempt, correlation_id: SecureRandom.uuid)
    expect do
      refused_typed_schema_write do
        JrcContactCenter::EndingDestinationExecution.create!(account: account, attempt: attempt, target_id: task.id)
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /native Project task audit required/)
    expect(JrcContactCenter::EndingDestinationExecution.where(account: account)).to be_empty
    expect(attempt.reload.outcome).to be_nil
  end

  it 'refuses an unrecognized native target instead of producing a success from a positive identifier' do
    attempt = typed_attempt(consent: typed_consent)
    expect do
      refused_typed_schema_write do
        JrcContactCenter::EndingDestinationExecution.create!(account: account, attempt: attempt, target_id: 8_000_000_000_000_000_000)
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /native Project task identity mismatch/)
    expect(JrcContactCenter::EndingDestinationExecution.where(account: account)).to be_empty
  end

  it 'rejects caller-supplied target class identity even when the native Task is real' do
    attempt = typed_attempt(consent: typed_consent)
    task = typed_native_task(attempt)
    expect do
      refused_typed_schema_write do
        JrcContactCenter::EndingDestinationExecution.create!(account: account, attempt: attempt,
                                                           target_id: task.id, target_type: 'JrcProjects::Task')
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /native success evidence is server generated/)
  end

  it 'rolls back the actual native Task and audit when writing success evidence fails' do
    attempt = typed_attempt(consent: typed_consent)
    tasks_before = JrcProjects::Task.where(account: account).count
    audits_before = JrcProjects::AuditEvent.where(account: account, action: 'projects.task.created').count
    expect do
      refused_typed_schema_write do
        task = typed_native_task(attempt)
        JrcContactCenter::EndingDestinationExecution.create!(account: account, attempt: attempt,
                                                           target_id: task.id, actor_user_id: actor.id)
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /native success evidence is server generated/)
    expect(JrcProjects::Task.where(account: account).count).to eq(tasks_before)
    expect(JrcProjects::AuditEvent.where(account: account, action: 'projects.task.created').count).to eq(audits_before)
    expect(JrcContactCenter::EndingDestinationExecution.where(account: account)).to be_empty
  end

  it 'rolls back a native effect and its success if the corresponding outcome cannot be persisted' do
    attempt = typed_attempt(consent: typed_consent)
    expect do
      refused_typed_schema_write do
        task = typed_native_task(attempt)
        execution = JrcContactCenter::EndingDestinationExecution.create!(account: account, attempt: attempt, target_id: task.id).reload
        JrcContactCenter::EndingDestinationOutcome.create!(account: account, attempt: attempt, execution: execution,
                                                          outcome: 'succeeded', result_code: 'SYNTHETIC_INVALID_RESULT')
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /cc_typed_outcome_result/)
    expect(JrcProjects::Task.where(account: account)).to be_empty
    expect(JrcProjects::AuditEvent.where(account: account, action: 'projects.task.created')).to be_empty
    expect(JrcContactCenter::EndingDestinationExecution.where(account: account)).to be_empty
    expect(attempt.reload.outcome).to be_nil
  end

  it 'does not turn a terminal failed attempt into a new native success' do
    attempt = failed_typed_attempt
    expect do
      refused_typed_schema_write do
        task = typed_native_task(attempt)
        JrcContactCenter::EndingDestinationExecution.create!(account: account, attempt: attempt, target_id: task.id)
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /terminal typed ending attempt cannot acquire another effect/)
    expect(JrcProjects::Task.where(account: account)).to be_empty
    expect(attempt.reload.outcome.outcome).to eq('failed')
  end

  it 'rejects rewriting a native typed success or replacing its target after persistence' do
    attempt = typed_attempt(consent: typed_consent)
    task = typed_native_task(attempt)
    execution = JrcContactCenter::EndingDestinationExecution.create!(account: account, attempt: attempt, target_id: task.id).reload
    query = "UPDATE jrc_contact_center_ending_destination_executions SET target_id = -1 WHERE id = #{execution.id}"
    expect { guarded_origin_sql(query) }.to raise_error(ActiveRecord::StatementInvalid, /native successes are immutable/)
    expect(execution.reload.target_id).to eq(task.id)
  end

  it 'does not allow later manual consent to rerun an already successful native destination' do
    attempt = typed_attempt(consent: typed_consent)
    task = typed_native_task(attempt)
    execution = JrcContactCenter::EndingDestinationExecution.create!(account: account, attempt: attempt, target_id: task.id).reload
    JrcContactCenter::EndingDestinationOutcome.create!(account: account, attempt: attempt, execution: execution,
                                                      outcome: 'succeeded', result_code: 'completed')
    expect { refused_typed_schema_write { typed_consent(key: SecureRandom.uuid) } }
      .to raise_error(ActiveRecord::StatementInvalid, /already succeeded/)
    expect(JrcProjects::Task.where(account: account).count).to eq(1)
    expect(described_class.where(account: account).count).to eq(1)
  end
end

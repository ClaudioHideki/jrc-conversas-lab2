# frozen_string_literal: true

require 'rails_helper'

# Actual PostgreSQL integrity coverage, prepared but not executed. These cases
# do not substitute for source/destination API authorization or browser proof.
RSpec.describe JrcContactCenter::EndingDestinationAttempt, type: :model do
  include_context 'with native typed ending schema evidence'

  it 'derives exact original metadata from real readiness and actual native ACW completion' do
    result = typed_context
    expect(result).to include('account_id' => account.id, 'origin_id' => typed_origin.id, 'version_id' => typed_version.id,
                              'actor_account_user_id' => member.id, 'actor_user_id' => actor.id,
                              'operation' => 'create_task', 'execution_mode' => 'agent_confirmation',
                              'trigger_kind' => 'ending_action_completion', 'rule_sha256' => typed_readiness.rule_sha256)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'refuses a foreign account instead of accepting its identifier as a grant' do
    typed_origin
    foreign = create(:account)
    expect { refused_typed_schema_write { typed_context(account_id: foreign.id) } }
      .to raise_error(ActiveRecord::StatementInvalid, /original unavailable/)
  end

  it 'refuses a missing prospective readiness rather than guessing a current review' do
    typed_origin
    expect { refused_typed_schema_write { typed_context(readiness_id: -1) } }
      .to raise_error(ActiveRecord::StatementInvalid, /prospective readiness unavailable/)
  end

  it 'does not treat an open native ACW or a reason draft as actual completion' do
    origin
    expect { refused_typed_schema_write { typed_context(origin_row: origin) } }
      .to raise_error(ActiveRecord::StatementInvalid, /actual native ACW completion required/)
    expect(qualification.reload.completed_at).to be_nil
    expect(JrcContactCenter::EndingDestinationConsent.where(account: account)).to be_empty
  end

  it 'keeps an intervening deactivation permanent after reactivation of the same rule' do
    typed_origin
    publish_typed_schema_definition('active' => false)
    publish_typed_schema_definition('active' => true)
    expect { refused_typed_schema_write { typed_context } }
      .to raise_error(ActiveRecord::StatementInvalid, /permanently blocked by deactivation/)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'records exact original-agent action consent separately without creating a business effect' do
    row = typed_consent
    expect(row.attributes).to include('version_id' => typed_version.id, 'actor_account_user_id' => member.id,
                                      'actor_user_id' => actor.id, 'operation' => 'create_task',
                                      'rule_sha256' => typed_readiness.rule_sha256)
    expect(row.integrity_sha256).to match(/\A[0-9a-f]{64}\z/)
    expect(described_class.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'refuses another account member as the original manual action confirmer' do
    typed_origin
    foreign_actor = create(:user, :contact_center_eligible, account: account, role: :administrator)
    other = account.account_users.find_by!(user: foreign_actor)
    expect { refused_typed_schema_write { typed_consent(actor_member_id: other.id) } }
      .to raise_error(ActiveRecord::StatementInvalid, /original-agent action consent required/)
    expect(JrcContactCenter::EndingDestinationConsent.where(account: account)).to be_empty
  end

  it 'refuses caller-provided generated consent identity' do
    typed_origin
    expect do
      refused_typed_schema_write do
        JrcContactCenter::EndingDestinationConsent.create!(account: account, origin: typed_origin, readiness: typed_readiness,
                                                           actor_account_user_id: member.id, actor_user_id: actor.id,
                                                           rule_code: 'SYNTHETIC_ORIGIN_RULE', destination_kind: 'project_task',
                                                           request_key: typed_key)
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /consent evidence is server generated/)
  end

  it 'rejects direct updates of an existing immutable manual action consent' do
    row = typed_consent
    digest = row.integrity_sha256
    expect { guarded_origin_sql("UPDATE jrc_contact_center_ending_destination_consents SET rule_code = 'SYNTHETIC_OTHER' WHERE id = #{row.id}") }
      .to raise_error(ActiveRecord::StatementInvalid, /action consent is immutable/)
    expect(row.reload.integrity_sha256).to eq(digest)
  end

  it 'rejects deleting a consent while its source account still exists' do
    row = typed_consent
    expect { guarded_origin_sql("DELETE FROM jrc_contact_center_ending_destination_consents WHERE id = #{row.id}") }
      .to raise_error(ActiveRecord::StatementInvalid, /action consent is immutable/)
  end

  it 'requires exact manual action consent before recording a typed manual attempt' do
    typed_origin
    expect { refused_typed_schema_write { typed_attempt } }
      .to raise_error(ActiveRecord::StatementInvalid, /Exact typed ending action consent required/)
    expect(described_class.where(account: account)).to be_empty
  end

  it 'binds consent to its exact request instead of using a preceding manual review' do
    consent = typed_consent
    expect { refused_typed_schema_write { typed_attempt(consent: consent, key: SecureRandom.uuid) } }
      .to raise_error(ActiveRecord::StatementInvalid, /Exact typed ending action consent required/)
    expect(described_class.where(account: account)).to be_empty
  end

  it 'persists one unfinished typed attempt with a server-derived stable effect key' do
    row = typed_attempt(consent: typed_consent)
    expect(row.effect_key).to eq(typed_key)
    expect(row.attributes).to include('actor_account_user_id' => member.id, 'actor_user_id' => actor.id,
                                      'version_id' => typed_version.id, 'operation' => 'create_task')
    expect(row.outcome).to be_nil
    expect(row.execution).to be_nil
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'rejects a second root attempt rather than inventing another pending delivery' do
    first = typed_attempt(consent: typed_consent)
    second_key = SecureRandom.uuid
    second_consent = typed_consent(key: second_key)
    expect { refused_typed_schema_write { typed_attempt(consent: second_consent, key: second_key) } }
      .to raise_error(ActiveRecord::StatementInvalid, /exact unsuccessful predecessor and original-agent review/)
    expect(described_class.where(account: account).pluck(:id)).to eq([first.id])
  end

  it 'refuses caller-provided attempt actor fields even when they name the original user' do
    consent = typed_consent
    expect { refused_typed_schema_write { typed_attempt(consent: consent, actor_user_id: actor.id) } }
      .to raise_error(ActiveRecord::StatementInvalid, /attempt evidence is server generated/)
  end

  it 'rejects rewriting an unfinished typed attempt with a different request key' do
    row = typed_attempt(consent: typed_consent)
    query = "UPDATE jrc_contact_center_ending_destination_attempts SET request_key = '#{SecureRandom.uuid}' WHERE id = #{row.id}"
    expect { guarded_origin_sql(query) }
      .to raise_error(ActiveRecord::StatementInvalid, /destination attempts are immutable/)
    expect(row.reload.request_key).to eq(typed_key)
  end

  it 'appends a bounded refusal without changing the immutable attempt or creating a native effect' do
    row = typed_attempt(consent: typed_consent)
    before = row.attributes
    result = JrcContactCenter::EndingDestinationOutcome.create!(account: account, attempt: row,
                                                                outcome: 'blocked', result_code: 'authorization_denied').reload
    expect(result.integrity_sha256).to match(/\A[0-9a-f]{64}\z/)
    expect(row.reload.attributes).to eq(before)
    expect(JrcProjects::Task.where(account: account)).to be_empty
    expect(JrcContactCenter::EndingDestinationExecution.where(account: account)).to be_empty
  end

  it 'refuses arbitrary failure text instead of storing sensitive exception contents' do
    row = typed_attempt(consent: typed_consent)
    expect do
      refused_typed_schema_write do
        JrcContactCenter::EndingDestinationOutcome.create!(account: account, attempt: row,
                                                           outcome: 'failed', result_code: 'SYNTHETIC_PRIVATE_MESSAGE')
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /cc_typed_outcome_result/)
    expect(row.reload.outcome).to be_nil
  end

  it 'rejects a successful outcome without a corresponding typed native execution' do
    row = typed_attempt(consent: typed_consent)
    expect do
      refused_typed_schema_write do
        JrcContactCenter::EndingDestinationOutcome.create!(account: account, attempt: row,
                                                           outcome: 'succeeded', result_code: 'completed')
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /native success identity mismatch/)
  end

  it 'does not rewrite a terminal result after a later manual review' do
    row = typed_attempt(consent: typed_consent)
    result = JrcContactCenter::EndingDestinationOutcome.create!(account: account, attempt: row,
                                                                outcome: 'failed', result_code: 'destination_failure').reload
    expect { guarded_origin_sql("UPDATE jrc_contact_center_ending_destination_outcomes SET outcome = 'succeeded' WHERE id = #{result.id}") }
      .to raise_error(ActiveRecord::StatementInvalid, /destination outcomes are immutable/)
    expect(result.reload.outcome).to eq('failed')
  end

  context 'with an explicit automatic rule' do
    let(:typed_mode) { 'automatic' }

    it 'records an automatic attempt without fabricating manual action consent' do
      row = typed_attempt
      expect(row.consent_id).to be_nil
      expect(row.effect_key).to eq(typed_key)
      expect(JrcContactCenter::EndingDestinationConsent.where(account: account)).to be_empty
    end

    it 'refuses to create manual consent for an automatic rule' do
      typed_origin
      expect { refused_typed_schema_write { typed_consent } }
        .to raise_error(ActiveRecord::StatementInvalid, /original-agent action consent required/)
    end
  end

  context 'with an unmarked legacy rule' do
    let(:typed_schema_marker) { false }

    it 'refuses to reinterpret historical rules as typed executable definitions' do
      typed_origin
      expect { refused_typed_schema_write { typed_context } }
        .to raise_error(ActiveRecord::StatementInvalid, /Explicit new typed ending rule required/)
      expect(described_class.where(account: account)).to be_empty
    end
  end
end

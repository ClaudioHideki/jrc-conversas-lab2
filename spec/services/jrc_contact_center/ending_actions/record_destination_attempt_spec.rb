# frozen_string_literal: true

require 'rails_helper'

# Actual PostgreSQL guards and technical persistence, prepared but not executed.
# These cases do not prove a public API, operational dispatch or source grants.
RSpec.describe JrcContactCenter::EndingActions::RecordDestinationAttempt do
  include_context 'with native typed ending schema evidence'

  let(:writer) do
    described_class.new(account: account, origin: typed_origin, readiness: typed_readiness,
                        rule_code: 'SYNTHETIC_ORIGIN_RULE', destination_kind: 'project_task')
  end

  it 'records the exact manual consent with server-derived metadata and no native business effect' do
    consent = typed_consent
    row = writer.call(request_key: typed_key, consent: consent)
    expect(row.attributes).to include('account_id' => account.id, 'origin_id' => typed_origin.id,
                                     'readiness_id' => typed_readiness.id, 'version_id' => typed_version.id,
                                     'actor_account_user_id' => member.id, 'actor_user_id' => actor.id,
                                     'consent_id' => consent.id, 'destination_kind' => 'project_task')
    expect(row.effect_key).to eq(typed_key)
    expect(JrcProjects::Task.where(account: account)).to be_empty
    expect(row.outcome).to be_nil
  end

  it 'acknowledges an exact repeated technical request without adding attempts or changing evidence' do
    consent = typed_consent
    first = writer.call(request_key: typed_key, consent: consent)
    before = first.attributes
    second = writer.call(request_key: typed_key, consent: consent)
    expect(second.id).to eq(first.id)
    expect(second.attributes).to eq(before)
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: account).count).to eq(1)
    expect(JrcContactCenter::EndingDestinationConsent.where(account: account).count).to eq(1)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'refuses to remove the original reviewed consent during replay' do
    first = writer.call(request_key: typed_key, consent: typed_consent)
    expect { writer.call(request_key: typed_key) }
      .to raise_error(JrcContactCenter::OperationError, 'ending_attempt_request_conflict')
    expect(first.reload.consent_id).not_to be_nil
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: account).count).to eq(1)
  end

  it 'does not reinterpret a request key as a different rule or destination' do
    consent = typed_consent
    first = writer.call(request_key: typed_key, consent: consent)
    changed = described_class.new(account: account, origin: typed_origin, readiness: typed_readiness,
                                  rule_code: 'SYNTHETIC_OTHER', destination_kind: 'service_desk')
    expect { changed.call(request_key: typed_key, consent: consent) }
      .to raise_error(JrcContactCenter::OperationError, 'ending_attempt_request_conflict')
    expect(first.reload.destination_kind).to eq('project_task')
    expect(first.rule_code).to eq('SYNTHETIC_ORIGIN_RULE')
  end

  it 'requires native manual action consent for a new manual attempt' do
    typed_origin
    expect { refused_typed_schema_write { writer.call(request_key: typed_key) } }
      .to raise_error(ActiveRecord::StatementInvalid, /Exact typed ending action consent required/)
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'does not manufacture a retry while the first attempt remains unfinished' do
    first = writer.call(request_key: typed_key, consent: typed_consent)
    next_key = SecureRandom.uuid
    consent = typed_consent(key: next_key)
    expect { refused_typed_schema_write { writer.call(request_key: next_key, consent: consent) } }
      .to raise_error(ActiveRecord::StatementInvalid, /exact unsuccessful predecessor and original-agent review/)
    expect(first.reload.outcome).to be_nil
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: account).count).to eq(1)
  end

  it 'records only the explicitly selected unsuccessful predecessor and preserves its effect identity' do
    first = failed_typed_attempt
    next_key = SecureRandom.uuid
    consent = typed_consent(key: next_key)
    row = writer.call(request_key: next_key, consent: consent, retry_of: first, reviewer: member)
    expect(row.retry_of_id).to eq(first.id)
    expect(row.retry_requested_by_account_user_id).to eq(member.id)
    expect(row.request_key).to eq(next_key)
    expect(row.effect_key).to eq(first.effect_key)
    expect(first.reload.outcome.outcome).to eq('failed')
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'refuses to substitute another reviewer on the same selected retry request' do
    first = failed_typed_attempt
    next_key = SecureRandom.uuid
    consent = typed_consent(key: next_key)
    row = writer.call(request_key: next_key, consent: consent, retry_of: first, reviewer: member)
    foreign_actor = create(:user, :contact_center_eligible, account: account, role: :administrator)
    other = account.account_users.find_by!(user: foreign_actor)
    expect { writer.call(request_key: next_key, consent: consent, retry_of: first, reviewer: other) }
      .to raise_error(JrcContactCenter::OperationError, 'ending_attempt_request_conflict')
    expect(row.reload.retry_requested_by_account_user_id).to eq(member.id)
  end

  it 'does not let a new retry request select another account member as the original reviewer' do
    first = failed_typed_attempt
    next_key = SecureRandom.uuid
    consent = typed_consent(key: next_key)
    foreign_actor = create(:user, :contact_center_eligible, account: account, role: :administrator)
    other = account.account_users.find_by!(user: foreign_actor)
    expect do
      refused_typed_schema_write do
        writer.call(request_key: next_key, consent: consent, retry_of: first, reviewer: other)
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /exact unsuccessful predecessor and original-agent review/)
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: account).count).to eq(1)
  end

  it 'does not borrow a technical replay from another account' do
    consent = typed_consent
    first = writer.call(request_key: typed_key, consent: consent)
    foreign = create(:account)
    other = described_class.new(account: foreign, origin: typed_origin, readiness: typed_readiness,
                                rule_code: 'SYNTHETIC_ORIGIN_RULE', destination_kind: 'project_task')
    expect { refused_typed_schema_write { other.call(request_key: typed_key, consent: consent) } }
      .to raise_error(ActiveRecord::StatementInvalid, /original unavailable/)
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: foreign)).to be_empty
    expect(first.reload.account_id).to eq(account.id)
  end

  it 'acknowledges old evidence after deactivation without removing its permanent execution block' do
    first = failed_typed_attempt
    publish_typed_schema_definition('active' => false)
    publish_typed_schema_definition('active' => true)
    acknowledged = writer.call(request_key: first.request_key, consent: first.consent)
    expect(acknowledged.id).to eq(first.id)
    expect { refused_typed_schema_write { typed_consent(key: SecureRandom.uuid) } }
      .to raise_error(ActiveRecord::StatementInvalid, /permanently blocked by deactivation/)
    expect(first.reload.outcome.outcome).to eq('failed')
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: account).count).to eq(1)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  context 'with an explicit automatic rule' do
    let(:typed_mode) { 'automatic' }

    it 'records an automatic attempt without creating manual action consent or a native effect' do
      row = writer.call(request_key: typed_key)
      expect(row.consent_id).to be_nil
      expect(row.actor_account_user_id).to eq(member.id)
      expect(row.effect_key).to eq(typed_key)
      expect(JrcContactCenter::EndingDestinationConsent.where(account: account)).to be_empty
      expect(JrcProjects::Task.where(account: account)).to be_empty
    end
  end
end

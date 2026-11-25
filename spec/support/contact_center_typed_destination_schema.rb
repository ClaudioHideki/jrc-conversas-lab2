# Synthetic SQL integrity fixtures only. Direct technical definition/readiness
# setup is not evidence that a public editor, API or permission grant exists.
RSpec.shared_context 'with native typed ending schema evidence' do
  include_context 'with native ending execution original evidence'

  let(:typed_mode) { 'agent_confirmation' }
  let(:typed_schema_marker) { true }
  let(:typed_key) { SecureRandom.uuid }
  let(:typed_version) { publish_typed_schema_definition }
  let(:typed_readiness) do
    JrcContactCenter::EndingActionReadiness.create!(account: account, version: typed_version, actor_account_user_id: member.id,
                                                    rule_code: 'SYNTHETIC_ORIGIN_RULE', request_key: SecureRandom.uuid).reload
  end
  let(:typed_origin) do
    origin
    complete_origin_qualification
    origin.reload
  end

  # Unlike an executor, this fixture is intentionally inside RSpec's synthetic
  # transaction. Native SQL guards, audit provenance and scope FKs remain live.
  def publish_typed_schema_definition(changes = {})
    JrcServiceDesk::NativeExecutionContext.with(account: account, account_user: member, user: actor) do
      account.with_lock do
        catalogue = JrcContactCenter::EndingActions::Catalogue.new(account: account)
        catalogue.verify_synchronized!
        document = typed_definition_changes(catalogue, changes)
        persist_typed_definition!(catalogue, document)
      end
    end
  end

  def typed_definition_changes(catalogue, changes)
    document = catalogue.call.deep_dup
    document['version'] += 1
    row = document.fetch('entries').find { |entry| entry.fetch('code') == 'SYNTHETIC_ORIGIN_RULE' }
    row['execution_mode'] = typed_mode
    row['destination_schema_version'] = 2 if typed_schema_marker
    row.merge!(changes)
    JrcContactCenter::EndingActions::RuleDefinition.new.call(document)
    document
  end

  def persist_typed_definition!(catalogue, document)
    before = JrcContactCenter::AcwPolicyAudit.capture(account)
    settings = account.settings.fetch(JrcContactCenter::AcwPolicy::KEY).merge(
      JrcContactCenter::EndingActions::Catalogue::KEY => catalogue.head_for(document)
    )
    account.update!(settings: account.settings.merge(JrcContactCenter::AcwPolicy::KEY => settings))
    audit = JrcContactCenter::AcwPolicyAudit.write!(account: account, before: before, after: JrcContactCenter::AcwPolicyAudit.capture(account))
    JrcContactCenter::EndingActionVersion.record_change!(account: account, definition: document, audit: audit)
    catalogue.verify_synchronized!
    JrcContactCenter::EndingActionVersion.where(account: account).order(revision: :desc).first!
  end

  def typed_context(account_id: account.id, origin_row: typed_origin, readiness_id: typed_readiness.id)
    query = [
      'SELECT cc_ending_destination_context(?, ?, ?, ?, ?)::text', account_id, origin_row.id, readiness_id,
      'SYNTHETIC_ORIGIN_RULE', 'project_task'
    ]
    query = ApplicationRecord.sanitize_sql_array(query)
    JSON.parse(ApplicationRecord.connection.select_value(query))
  end

  def typed_consent(key: typed_key, actor_member_id: member.id, origin_row: typed_origin)
    JrcContactCenter::EndingDestinationConsent.create!(account: account, origin: origin_row, readiness: typed_readiness,
                                                       actor_account_user_id: actor_member_id, rule_code: 'SYNTHETIC_ORIGIN_RULE',
                                                       destination_kind: 'project_task', request_key: key).reload
  end

  def typed_attempt(consent: nil, key: typed_key, **attributes)
    JrcContactCenter::EndingDestinationAttempt.create!(account: account, origin: typed_origin, readiness: typed_readiness,
                                                       rule_code: 'SYNTHETIC_ORIGIN_RULE', destination_kind: 'project_task',
                                                       request_key: key, consent: consent, **attributes).reload
  end

  def refused_typed_schema_write(&)
    ApplicationRecord.transaction(requires_new: true, &)
  end

  def typed_native_task(attempt, correlation_id: attempt.effect_key)
    document = attempt.origin.version.definition
    rule = document.fetch('entries').find { |entry| entry.fetch('code') == attempt.rule_code }
    parameters = rule.fetch('actions').find { |entry| entry.fetch('kind') == 'project_task' }.fetch('parameters')
    JrcServiceDesk::NativeExecutionContext.with(account: account, account_user: member, user: actor) do
      JrcContactCenter::EndingActions::ProjectTaskDestination.new(account: account, member: member).call(
        parameters: parameters, trigger_at: attempt.triggered_at, timezone: typed_readiness.source_timezone, correlation_id: correlation_id
      )
    end
  end

  def failed_typed_attempt
    row = typed_attempt(consent: typed_consent)
    JrcContactCenter::EndingDestinationOutcome.create!(account: account, attempt: row, outcome: 'failed', result_code: 'destination_failure')
    row.reload
  end

  before { typed_readiness }
end

# frozen_string_literal: true

require 'json'
require 'digest'
require 'webmock'
require_relative 'jrc_call_center_synthetic_password'

# Prepare an actual M18 baseline in a separate Rails runner before RSpec's
# normal schema-maintenance gate. Never disable that gate or borrow a live DB.
class JrcContactCenter::SyntheticEndingExecutionUpgrade
  DATABASE = 'jrc_cc_ending_success_upgrade_synthetic'
  TABLE = :jrc_contact_center_ending_action_executions
  BEFORE = '/tmp/call-center-ending-success-before.json'
  AFTER = '/tmp/call-center-ending-success-upgrade.json'
  TYPES = %w[JrcContactCenter::CallSession JrcContactCenter::CallLeg JrcContactCenter::Qualification
             JrcContactCenter::EndingActionOrigin JrcContactCenter::EndingActionCompletion JrcContactCenter::EndingActionVersion
             JrcContactCenter::EndingActionQueueScope Account AccountUser User JrcContactCenter::EndingActionReadiness
             JrcProjects::Project JrcProjects::Task JrcProjects::AuditEvent].freeze

  def self.prepare!
    new.prepare
  end

  def self.verify!
    new.verify
  end

  def prepare
    guard!(installed: false)
    create_identity
    JrcServiceDesk::NativeExecutionContext.with(account: @account, account_user: @member, user: @member.user) do
      create_configuration
      activate_rule
      create_attendance
      create_existing_task
    end
    proof = { sha: ENV.fetch('GITHUB_SHA'), synthetic: true, account_id: @account.id, records: records.map { |row| snapshot(row) } }
    File.write(BEFORE, JSON.pretty_generate(proof))
  end

  def verify
    guard!(installed: true)
    before = load_baseline!
    records = before.fetch('records')
    records.each { |row| verify_record!(row) }
    require Rails.root.join('db/migrate/20261124000000_create_contact_center_ending_action_executions')
    CreateContactCenterEndingActionExecutions.new.up
    records.each { |row| verify_record!(row) }
    verify_empty_metadata_and_effects!
    result = upgrade_report(before)
    File.write(AFTER, JSON.pretty_generate(result))
    result
  end

  private

  def guard!(installed:)
    config = ApplicationRecord.connection_db_config
    owned = runner_owned? && config.configuration_hash[:host] == '127.0.0.1' && config.database == DATABASE &&
            ApplicationRecord.connection.current_database == DATABASE
    raise 'Exclusive readiness upgrade database required' unless owned

    verify_schema_stage!(installed: installed)
    ActiveJob::Base.queue_adapter = :test
    WebMock.enable!
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  def runner_owned?
    ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' && Rails.env.test? &&
      ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15'
  end

  def verify_schema_stage!(installed:)
    raise 'Committed success upgrade baseline required' if ApplicationRecord.connection.transaction_open?
    raise 'Unexpected success installation stage' unless ApplicationRecord.connection.table_exists?(TABLE) == installed
    tables = %i[jrc_contact_center_ending_action_readinesses jrc_contact_center_ending_action_origins]
    raise 'Native M18 readiness and origin schemas required' unless tables.all? { |table| ApplicationRecord.connection.table_exists?(table) }
  end

  def load_baseline!
    before = JSON.parse(File.read(BEFORE))
    raise 'Readiness upgrade source identity mismatch' unless before.fetch('sha') == ENV.fetch('GITHUB_SHA') && before.fetch('synthetic') == true

    @account = Account.find(before.fetch('account_id'))
    raise 'Synthetic readiness upgrade account required' unless @account.name == 'SYNTHETIC ending success upgrade'

    before
  end

  def verify_empty_metadata_and_effects!
    raise 'Installation cannot invent old successes' unless JrcContactCenter::EndingActionExecution.count.zero?
    raise 'Installation changed existing tasks' unless JrcProjects::Task.where(account: @account).count == 1
    raise 'Installation changed explicit activation history' unless JrcContactCenter::EndingActionReadiness.where(account: @account).count == 1
  end

  def upgrade_report(before)
    { sha: before.fetch('sha'), synthetic: true, preserved_records: before.fetch('records'),
      exact_old_columns_and_values_preserved: true, existing_tasks_preserved: 1, readiness_records_preserved: 1,
      successful_receipts: 0, operational_effects_delta: 0, rerun_idempotent: true }
  end

  def create_identity
    @account = Account.create!(name: 'SYNTHETIC ending success upgrade')
    @account.enable_features!('jrc_contact_center', 'jrc_projects')
    user = User.new(name: 'SYNTHETIC readiness original agent', email: "cc-readiness-#{SecureRandom.hex(8)}@example.test",
                    password: JrcContactCenter::SyntheticPassword.generate, confirmed_at: Time.current)
    user.skip_confirmation_notification!
    user.save!
    @member = AccountUser.create!(account: @account, user: user, role: :administrator, jrc_projects_enabled: true,
                                  jrc_projects_permissions: { 'projects.project.create' => true })
    JrcContactCenter::AccessGrant.create!(account: @account, account_user: @member, eligible: true)
    JrcCrm::UserBusinessUnit.create!(account: @account, user: user, scope: 'GROUP', active: true, structure_managed: true)
  end

  def create_configuration
    issuer = @account.master_companies.create!(name: 'SYNTHETIC readiness issuer', relationship_type: 'internal', active: true)
    business = JrcCrm::BusinessUnit.create!(account: @account, operating_company: issuer, code: 'SYNTHETIC', name: 'SYNTHETIC business')
    unit = JrcContactCenter::Unit.create!(account: @account, code: 'SYNTHETIC', name: 'SYNTHETIC operational', kind: 'sac',
                                          settings: { issuer_company_id: issuer.id, business_unit_id: business.id })
    @queue = JrcContactCenter::Queue.create!(account: @account, unit: unit, code: 'SYNTHETIC', name: 'SYNTHETIC queue')
    policy = JrcContactCenter::AcwPolicy.new(account: @account)
    reason = { code: 'SYNTHETIC_UPGRADE_REASON', name: 'SYNTHETIC reason', category: 'SYNTHETIC', description: '', order: 0, active: true }
    policy.update!({ voice: 180, whatsapp: 180 }, voice_reason_catalog: [reason], voice_reason_required_queue_ids: [@queue.id.to_s],
                                                  voice_reason_confirmation: true, expected_revision: policy.revision)
    configure_rule(policy)
  end

  def configure_rule(policy)
    project = JrcProjects::Projects::Create.call(account: @account, actor: @member.user,
                                                 attributes: { name: 'SYNTHETIC readiness destination' }, idempotency_key: SecureRandom.uuid)
    @project = project
    @scope = JrcContactCenter::EndingActionQueueScope.where(account: @account, source_queue_id: @queue.id).order(:revision).last!
    values = { title: 'SYNTHETIC unarmed task', priority: 'medium', estimated_minutes: 0,
               board_column_id: project.board_columns.find_by!(status_key: 'backlog').id.to_s }
    input = { code: 'SYNTHETIC_UPGRADE_RULE', name: 'SYNTHETIC prospective rule', reason_code: 'SYNTHETIC_UPGRADE_REASON',
              queue_id: @queue.id.to_s, scope_revision: @scope.integrity_sha256, timing: 'acw_completed', active: true,
              execution_mode: 'automatic', conditions: { outcome_codes: [] },
              actions: [{ kind: 'project_task', parameters: { project_id: project.id.to_s, due_after_days: nil, attributes: values } }] }
    JrcContactCenter::EndingActions::ConfigureRule.new(account: @account, member: @member, input: input,
                                                       expected_revision: policy.revision).call
  end

  def activate_rule
    @readiness = JrcContactCenter::EndingActions::ActivateRule.new(
      account: @account, member: @member, rule_code: 'SYNTHETIC_UPGRADE_RULE', request_key: SecureRandom.uuid,
      expected_revision: JrcContactCenter::AcwPolicy.new(account: @account).revision
    ).call
  end

  def create_existing_task
    values = { title: 'SYNTHETIC existing manual task', priority: 'medium', estimated_minutes: 0,
               board_column_id: @project.board_columns.find_by!(status_key: 'backlog').id }
    @existing_task = JrcProjects::Tasks::Create.call(account_user: @member, project: @project, attributes: values,
                                                     correlation_id: SecureRandom.uuid)
    @existing_audit = JrcProjects::AuditEvent.where(account: @account, auditable_type: @existing_task.class.name,
                                                    auditable_id: @existing_task.id, action: 'projects.task.created').sole
  end

  def create_attendance
    @call = JrcContactCenter::CallSession.create!(account: @account, provider: 'synthetic', correlation_id: SecureRandom.uuid,
                                                  direction: 'inbound', status: 'connected', started_at: Time.current, answered_at: Time.current,
                                                  current_unit: @queue.unit, current_queue: @queue)
    @leg = JrcContactCenter::CallLeg.create!(account: @account, call_session: @call, account_user: @member, queue: @queue,
                                             direction: 'inbound', status: 'connected', started_at: @call.started_at, answered_at: @call.answered_at)
    @call.update!(status: 'ended', ended_at: Time.current)
    @qualification = JrcContactCenter::Qualification.find_by!(account: @account, account_user: @member, call_session: @call)
    @origin = JrcContactCenter::EndingActionOrigin.find_by!(account: @account, source_qualification_id: @qualification.id)
    JrcContactCenter::QualificationManager.new(account: @account, member: @member).complete!(
      @qualification, { reason_code: 'SYNTHETIC_UPGRADE_REASON', outcome_code: 'completed' }
    )
    @completion = JrcContactCenter::EndingActionCompletion.find_by!(account: @account, origin: @origin)
  end

  def records
    [@call, @leg, @qualification, @origin, @completion, @origin.version, @scope, @account, @member, @member.user,
     @readiness, @project, @existing_task, @existing_audit]
  end

  def snapshot(record)
    stored = record.reload
    { type: stored.class.name, id: stored.id, columns: stored.attributes.keys,
      sha256: Digest::SHA256.hexdigest(ActiveSupport::JSON.encode(stored.attributes)) }
  end

  def verify_record!(row)
    type = row.fetch('type')
    raise 'Unknown upgrade record type' unless TYPES.include?(type)

    actual = case type
             when 'Account' then @account
             when 'User' then @account.users.find(row.fetch('id'))
             else type.constantize.where(account_id: @account.id).find(row.fetch('id'))
             end
    raise 'Original native upgrade record changed' unless snapshot(actual).stringify_keys == row
  end
end

# frozen_string_literal: true

require 'json'
require 'digest'
require_relative 'jrc_call_center_synthetic_password'

# Private preparation, not invoked. Only an exclusive ephemeral database may
# create these synthetic identities. No token, password or raw snapshot is emitted.
class JrcContactCenter::SyntheticEndingOriginUpgrade
  DATABASE = 'jrc_cc_ending_origin_upgrade_synthetic'
  BEFORE = '/tmp/call-center-ending-origin-upgrade-before.json'
  AFTER = '/tmp/call-center-ending-origin-upgrade-after.json'
  TABLE = 'jrc_contact_center_ending_action_origins'

  def self.prepare!
    new.prepare
  end

  def self.verify!
    new.verify
  end

  def prepare
    guard!(installed: false)
    raise 'Synthetic upgrade already prepared' if File.exist?(BEFORE)

    create_identity
    create_scope
    JrcServiceDesk::NativeExecutionContext.with(account: @account, account_user: @member, user: @member.user) do
      configure_native_ending
      create_attendance
    end
    record = { sha: ENV.fetch('GITHUB_SHA'), synthetic: true, account_id: @account.id, member_id: @member.id,
               records: [@call, @leg, @qualification].map { |row| snapshot(row) },
               settings_digest: digest(@account.reload.settings),
               version_ids: JrcContactCenter::EndingActionVersion.where(account: @account).pluck(:id) }
    File.write(BEFORE, JSON.pretty_generate(record) + "\n")
  end

  def verify
    guard!(installed: true)
    previous = JSON.parse(File.read(BEFORE))
    raise 'Upgrade identity mismatch' unless previous.fetch('sha') == ENV.fetch('GITHUB_SHA') && previous.fetch('synthetic') == true

    @account = Account.find(previous.fetch('account_id'))
    @member = @account.account_users.find(previous.fetch('member_id'))
    raise 'Synthetic upgrade account required' unless @account.name == 'SYNTHETIC ending origin upgrade'

    verify_preserved!(previous)
    replay_native_attendance!(previous)
    report = { sha: previous.fetch('sha'), synthetic: true, preserved_before_replay: true, legacy_origin_backfilled: false,
               native_legacy_completion_preserved: true, operational_effects: 0, passed: true }
    File.write(AFTER, JSON.pretty_generate(report) + "\n")
  end

  private

  def guard!(installed:)
    config = ApplicationRecord.connection_db_config
    owned = ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' && Rails.env.test? &&
            config.database == DATABASE && config.configuration_hash[:host] == '127.0.0.1' &&
            ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' && ENV.fetch('GITHUB_SHA', '').match?(/\A[0-9a-f]{40}\z/)
    raise 'Exclusive disposable origin upgrade runner required' unless owned
    raise 'Unexpected origin installation stage' unless ApplicationRecord.connection.table_exists?(TABLE) == installed

    ActiveJob::Base.queue_adapter = :test
  end

  def create_identity
    @account = Account.create!(name: 'SYNTHETIC ending origin upgrade')
    @account.enable_features!('jrc_contact_center', 'jrc_projects')
    user = User.new(name: 'SYNTHETIC original agent', email: "cc-origin-#{SecureRandom.hex(8)}@example.test",
                    password: JrcContactCenter::SyntheticPassword.generate, confirmed_at: Time.current)
    user.skip_confirmation_notification!
    user.save!
    @member = AccountUser.create!(account: @account, user: user, role: :administrator, jrc_projects_enabled: true,
                                  jrc_projects_permissions: { 'projects.project.create' => true })
    JrcContactCenter::AccessGrant.create!(account: @account, account_user: @member, eligible: true)
    JrcCrm::UserBusinessUnit.create!(account: @account, user: user, scope: 'GROUP', active: true, structure_managed: true)
  end

  def create_scope
    issuer = @account.master_companies.create!(name: 'SYNTHETIC upgrade issuer', relationship_type: 'internal', active: true)
    business = JrcCrm::BusinessUnit.create!(account: @account, operating_company: issuer, code: 'SYNTHETIC', name: 'SYNTHETIC upgrade unit')
    unit = JrcContactCenter::Unit.create!(account: @account, code: 'SYNTHETIC', name: 'SYNTHETIC upgrade operational', kind: 'sac',
                                          settings: { issuer_company_id: issuer.id, business_unit_id: business.id })
    @queue = JrcContactCenter::Queue.create!(account: @account, unit: unit, code: 'SYNTHETIC', name: 'SYNTHETIC upgrade queue')
  end

  def configure_native_ending
    policy = JrcContactCenter::AcwPolicy.new(account: @account)
    entry = { code: 'SYNTHETIC_UPGRADE_REASON', name: 'SYNTHETIC upgrade reason', category: 'SYNTHETIC', description: '', order: 0, active: true }
    policy.update!({ voice: 180, whatsapp: 180 }, voice_reason_catalog: [entry], voice_reason_required_queue_ids: [@queue.id.to_s],
                                                  voice_reason_confirmation: true, expected_revision: policy.revision)
    project = JrcProjects::Projects::Create.call(account: @account, actor: @member.user,
                                                 attributes: { name: 'SYNTHETIC upgrade destination' }, idempotency_key: SecureRandom.uuid)
    scope = JrcContactCenter::EndingActionQueueScope.where(account: @account, source_queue_id: @queue.id).order(:revision).last!
    JrcContactCenter::EndingActions::ConfigureRule.new(account: @account, member: @member, input: rule_document(project, scope),
                                                       expected_revision: policy.revision).call
  end

  def rule_document(project, scope)
    attributes = { 'title' => 'SYNTHETIC unarmed upgrade', 'priority' => 'medium', 'estimated_minutes' => 0,
                   'board_column_id' => project.board_columns.find_by!(status_key: 'backlog').id.to_s }
    parameters = { 'project_id' => project.id.to_s, 'due_after_days' => nil, 'attributes' => attributes }
    { 'code' => 'SYNTHETIC_UPGRADE_RULE', 'name' => 'SYNTHETIC upgrade rule', 'reason_code' => 'SYNTHETIC_UPGRADE_REASON',
      'queue_id' => @queue.id.to_s, 'scope_revision' => scope.integrity_sha256, 'active' => true, 'timing' => 'acw_completed',
      'execution_mode' => 'automatic', 'conditions' => { 'outcome_codes' => [] },
      'actions' => [{ 'kind' => 'project_task', 'parameters' => parameters }] }
  end

  def create_attendance
    @call = JrcContactCenter::CallSession.create!(account: @account, provider: 'synthetic', correlation_id: SecureRandom.uuid,
                                                 direction: 'inbound', status: 'connected', started_at: Time.current,
                                                 current_unit: @queue.unit, current_queue: @queue)
    @leg = JrcContactCenter::CallLeg.create!(account: @account, call_session: @call, account_user: @member, queue: @queue,
                                            direction: 'inbound', status: 'connected', started_at: @call.started_at, answered_at: Time.current)
    @call.update!(status: 'ended', ended_at: Time.current)
    @qualification = JrcContactCenter::Qualification.find_by!(account: @account, account_user: @member, call_session: @call)
  end

  def snapshot(record)
    { type: record.class.name, id: record.id, columns: record.attributes.keys, digest: digest(record.attributes) }
  end

  def digest(value)
    Digest::SHA256.hexdigest(ActiveSupport::JSON.encode(value))
  end

  def verify_preserved!(previous)
    classes = [JrcContactCenter::CallSession, JrcContactCenter::CallLeg, JrcContactCenter::Qualification].index_by(&:name)
    previous.fetch('records').each do |saved|
      record = classes.fetch(saved.fetch('type')).where(account: @account).find(saved.fetch('id'))
      raise 'Original source changed during upgrade' unless digest(record.attributes.slice(*saved.fetch('columns'))) == saved.fetch('digest')
    end
    raise 'Original configuration changed' unless digest(@account.settings) == previous.fetch('settings_digest')
    versions = JrcContactCenter::EndingActionVersion.where(account: @account).pluck(:id)
    raise 'Original versions changed' unless versions == previous.fetch('version_ids')
    raise 'Legacy source unexpectedly backfilled' if JrcContactCenter::EndingActionOrigin.where(account: @account).exists?
  end

  def replay_native_attendance!(previous)
    call_id = previous.fetch('records').find { |row| row.fetch('type') == JrcContactCenter::CallSession.name }.fetch('id')
    call = JrcContactCenter::CallSession.where(account: @account).find(call_id)
    raise 'Legacy leg was retrospectively pinned' if call.legs.where.not(ending_action_scope_version_id: nil).exists?

    JrcContactCenter::QualificationManager.ensure_voice!(call)
    qualification = JrcContactCenter::Qualification.find_by!(account: @account, account_user: @member, call_session: call)
    JrcContactCenter::QualificationManager.new(account: @account, member: @member).complete!(
      qualification, { reason_code: 'SYNTHETIC_UPGRADE_REASON', outcome_code: 'completed' }
    )
    raise 'Native legacy completion failed' unless qualification.reload.completed_at
    raise 'Legacy replay created an origin' if JrcContactCenter::EndingActionOrigin.where(account: @account).exists?
    raise 'Legacy replay created a completion' if JrcContactCenter::EndingActionCompletion.where(account: @account).exists?
    raise 'Upgrade caused an operational effect' if JrcProjects::Task.where(account: @account).exists?
  end
end

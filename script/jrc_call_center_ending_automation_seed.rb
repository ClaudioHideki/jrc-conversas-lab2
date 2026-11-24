# frozen_string_literal: true

# Called only by SyntheticPauseSeed after its exclusive disposable-runner guard.
class JrcContactCenter::SyntheticEndingAutomationSeed
  PROJECT_PERMISSIONS = %w[jrc_projects_project_view jrc_projects_project_create jrc_projects_task_create jrc_projects_task_view
                           jrc_projects_task_assign jrc_projects_task_update jrc_projects_member_view].freeze

  def self.call(account:, admin:, queue:)
    new(account: account, admin: admin, queue: queue).call
  end

  def initialize(account:, admin:, queue:)
    @account = account
    @admin = admin
    @queue = queue
  end

  def call
    @account.enable_features!('jrc_projects')
    @admin.update!(jrc_projects_enabled: true, jrc_projects_permissions: { 'projects.project.create' => true })
    @admin.custom_role.update!(permissions: (@admin.custom_role.permissions + PROJECT_PERMISSIONS).uniq)
    JrcServiceDesk::NativeExecutionContext.with(account: @account, account_user: @admin, user: @admin.user) { prepare_configuration }
  end

  private

  def prepare_configuration
    policy = JrcContactCenter::AcwPolicy.new(account: @account)
    reason = { code: 'SYNTHETIC_AUTOMATION', name: 'SYNTHETIC automation reason', category: 'SYNTHETIC',
               description: '', order: 0, active: true }
    policy.update!({ voice: 180, whatsapp: 180 }, voice_reason_catalog: [reason], voice_reason_required_queue_ids: [@queue.id.to_s],
                                                  voice_reason_confirmation: true, expected_revision: policy.revision)
    project = JrcProjects::Projects::Create.call(account: @account, actor: @admin.user,
                                                 attributes: { name: 'SYNTHETIC ending automation project' }, idempotency_key: SecureRandom.uuid)
    { automation_project_id: project.id.to_s, automation_project_name: project.name,
      automation_column_id: project.board_columns.find_by!(status_key: 'backlog').id.to_s,
      automation_assignee_id: @admin.user_id.to_s, automation_reason: reason.fetch(:code) }
  end
end

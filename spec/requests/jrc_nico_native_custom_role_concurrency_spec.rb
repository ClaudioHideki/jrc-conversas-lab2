require 'rails_helper'

RSpec.describe 'NICO native task effect versus custom permission revocation', type: :request, sd_concurrency: true do
  self.use_transactional_tests = false
  include JrcServiceDeskConcurrency

  before do
    @account = create(:account, custom_attributes: { 'nico_enabled' => true })
    @account.enable_features!('jrc_projects')
    @owner = create(:user, account: @account, role: :administrator)
    @actor = create(:user, account: @account, role: :agent)
    @custom_role = create(:custom_role, account: @account,
      permissions: %w[jrc_projects_project_view jrc_projects_task_view jrc_projects_task_update])
    @account.account_users.find_by!(user_id: @actor.id).update!(custom_role: @custom_role, jrc_projects_enabled: true)
    @project = JrcProjects::Project.create!(account: @account, owner: @owner, key: 'CUSTOM_FENCE',
      name: 'Native project', status: 'planned', visibility: 'account')
    @project.project_members.create!(account: @account, user: @actor, role: 'member', allocation_percent: 0)
    @task = JrcProjects::Task.create!(account: @account, project: @project, created_by: @owner,
      title: 'Original task', status: 'backlog', priority: 'medium', estimated_minutes: 0)
  end

  after do
    if @account
      JrcProjects::AuditEvent.where(account_id: @account.id).delete_all
      JrcNico::Session.where(account_id: @account.id).destroy_all
      @project&.reload&.destroy!
      @account.reload.destroy!
    end
    @actor&.reload&.destroy!
    @owner&.reload&.destroy!
  end

  it 'does not commit a task edit after the effective custom permission was revoked' do
    expect(@project.project_members.find_by!(user_id: @actor.id).role).to eq('member')
    operator = JrcNico::OperatorSession.new(account: @account, user: @actor)
    command = operator.ask(message: 'Synthetic reviewed edit', request_id: SecureRandom.uuid, prepared: {
      'tool' => 'update_project_task', 'arguments' => { 'project_id' => @project.id, 'task_id' => @task.id,
        'lock_version' => 0, 'title' => 'Reviewed task' }
    })
    operator.execute(command)
    operator.browser_claim(command)
    actor_headers = @actor.create_new_auth_token.merge('X-JRC-Nico-Command-Id' => command.id.to_s,
      'X-JRC-Nico-Contract' => 'nico-native-v1')
    owner_headers = @owner.create_new_auth_token
    account_id, role_id, task_id = @account.id, @custom_role.id, @task.id
    path = "/api/v1/accounts/#{account_id}/projects/projects/#{@project.id}/tasks/#{task_id}"
    effect_ready = Queue.new
    revoker_backend = Queue.new
    revocation_finished = Queue.new
    observation = {}

    # Keep the real controller, policy, transaction, save and audit. Pause only
    # this fixture's save, after TasksController's final authorize_capability!.
    allow_any_instance_of(JrcProjects::Task).to receive(:save!).and_wrap_original do |original, *args, **kwargs|
      if original.receiver.id == task_id && original.receiver.title == 'Reviewed task'
        effect_backend = ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()').to_i
        effect_ready << true
        revoker_pid = Timeout.timeout(10) { revoker_backend.pop }
        Timeout.timeout(10) do
          loop do
            # Lock state changes without SQL writes by this request; the Rails
            # query cache must not freeze the observer's first false result.
            blocked = ActiveRecord::Base.uncached do
              ActiveRecord::Base.connection.select_value("SELECT #{effect_backend} = ANY(pg_blocking_pids(#{revoker_pid}))")
            end
            break if blocked || !revocation_finished.empty?

            sleep 0.01
          end
        end
        observation[:permissions_before_effect] = ActiveRecord::Base.uncached { CustomRole.find(role_id).permissions }
      end
      original.call(*args, **kwargs)
    end

    outcomes = concurrently([
      lambda do
        client = ActionDispatch::Integration::Session.new(Rails.application)
        client.patch(path, params: { task: { title: 'Reviewed task', lock_version: 0 } }, headers: actor_headers, as: :json)
        [:task_status, client.response.status]
      end,
      lambda do
        Timeout.timeout(10) { effect_ready.pop }
        revoker_backend << ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()').to_i
        client = ActionDispatch::Integration::Session.new(Rails.application)
        client.patch("/api/v1/accounts/#{account_id}/custom_roles/#{role_id}",
          params: { custom_role: { permissions: %w[jrc_projects_project_view jrc_projects_task_view] } }, headers: owner_headers, as: :json)
        [:role_status, client.response.status]
      ensure
        revocation_finished << true
      end
    ])
    errors = outcomes.grep(Exception).map { |error| "#{error.class}: #{error.message.lines.first}" }
    expect(errors).to be_empty
    expect(outcomes.to_h.fetch(:role_status)).to eq(200)
    expect(@custom_role.reload.permissions).not_to include('jrc_projects_task_update')
    if @task.reload.title == 'Reviewed task'
      # The native CustomRolesController updates the actual permissions row,
      # independently of the AccountUser and ProjectMember grants.
      expect(observation[:permissions_before_effect]).to include('jrc_projects_task_update')
      expect(outcomes.to_h.fetch(:task_status)).to eq(200)
      expect(@task.lock_version).to eq(1)
      expect(JrcProjects::AuditEvent.where(account_id: account_id, action: 'projects.task.updated').count).to eq(1)
      expect(command.reload.execution_context.dig('native_browser_command', 'consumed_at')).to be_present
    else
      expect(@task).to have_attributes(title: 'Original task', lock_version: 0)
      expect(outcomes.to_h.fetch(:task_status)).to eq(403)
      expect(JrcProjects::AuditEvent.where(account_id: account_id, action: 'projects.task.updated')).not_to exist
    end
    expect(command.reload.status).to eq('executing')
  end
end

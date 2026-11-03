require 'rails_helper'

RSpec.describe 'NICO browser command versus native project audit locking', :sd_concurrency do
  self.use_transactional_tests = false
  include JrcServiceDeskConcurrency

  before do
    @fixture_account = create(:account, custom_attributes: { 'nico_enabled' => true })
    @fixture_account.enable_features!('jrc_projects')
    @fixture_user = create(:user, account: @fixture_account, role: :administrator)
    @fixture_project = JrcProjects::Project.create!(account: @fixture_account, owner: @fixture_user,
      key: 'FENCE_RACE', name: 'Original project', status: 'planned', visibility: 'account')
    @fixture_task = JrcProjects::Task.create!(account: @fixture_account, project: @fixture_project, created_by: @fixture_user,
      title: 'Original task', status: 'backlog', priority: 'medium', estimated_minutes: 0)
  end

  after do
    # Only rows created by this example; never truncate the shared test database.
    if @fixture_account
      JrcProjects::AuditEvent.where(account_id: @fixture_account.id).delete_all
      JrcNico::Session.where(account_id: @fixture_account.id).destroy_all
      @fixture_project&.reload&.destroy!
      @fixture_account.reload.destroy!
    end
    @fixture_user&.reload&.destroy!
  end

  it 'commits a native human audit and one claimed task edit without an Account/Project lock cycle' do
    operator = JrcNico::OperatorSession.new(account: @fixture_account, user: @fixture_user)
    command = operator.ask(message: 'Synthetic reviewed task edit', request_id: SecureRandom.uuid, prepared: {
      'tool' => 'update_project_task', 'arguments' => { 'project_id' => @fixture_project.id, 'task_id' => @fixture_task.id,
        'lock_version' => @fixture_task.lock_version, 'title' => 'Reviewed task' }
    })
    operator.execute(command)
    operator.browser_claim(command)
    expect(command.reload.status).to eq('executing')
    expect(command.execution_context.fetch('native_browser_command')['consumed_at']).to be_nil

    account_id, user_id, project_id, task_id = @fixture_account.id, @fixture_user.id, @fixture_project.id, @fixture_task.id
    request = Struct.new(:headers, :request_method, :path, :query_string, :request_parameters).new(
      { 'X-JRC-Nico-Command-Id' => command.id.to_s, 'X-JRC-Nico-Contract' => 'nico-native-v1' },
      'PATCH', "/api/v1/accounts/#{account_id}/projects/projects/#{project_id}/tasks/#{task_id}", '',
      { 'task' => { 'title' => 'Reviewed task', 'lock_version' => 0 } }
    )
    project_locked = Queue.new
    account_locked = Queue.new
    outcomes = concurrently([
      lambda do
        project = JrcProjects::Project.find(project_id)
        project.with_lock do
          ActiveRecord::Base.connection.execute("SET LOCAL statement_timeout='10s'")
          project_locked << true
          Timeout.timeout(10) { account_locked.pop }
          # Mirrors native Project -> audit ordering. The audit FK needs KEY SHARE
          # on Account while the NICO command holds its serialization lock there.
          before = project.attributes
          project.update!(name: 'Human project edit')
          JrcProjects::AuditEvent.record!(account: Account.find(account_id), actor: User.find(user_id),
            action: 'projects.project.updated', auditable: project, before_data: before, after_data: project.attributes)
        end
        :human_committed
      end,
      lambda do
        Timeout.timeout(10) { project_locked.pop }
        ActiveRecord::Base.transaction do
          ActiveRecord::Base.connection.execute("SET LOCAL statement_timeout='10s'")
          JrcNico::NativeBrowserCommand.execute(account: Account.find(account_id), user: User.find(user_id), request: request) do
            account_locked << true # real command validation already holds Account and Command
            JrcProjects::Project.find(project_id).with_lock do
              task = JrcProjects::Task.find(task_id)
              before = task.attributes
              task.update!(title: 'Reviewed task')
              JrcProjects::AuditEvent.record!(account: Account.find(account_id), actor: User.find(user_id),
                action: 'projects.task.updated', auditable: task, before_data: before, after_data: task.attributes)
            end
            200 # the controller supplies its selected native response status
          end
        end
        :nico_committed
      end
    ])
    descriptions = outcomes.map { |result| result.is_a?(Exception) ? "#{result.class}: #{result.message.lines.first}" : result }
    expect(descriptions).to contain_exactly(:human_committed, :nico_committed)
    expect(@fixture_project.reload.name).to eq('Human project edit')
    expect(@fixture_task.reload).to have_attributes(title: 'Reviewed task', lock_version: 1)
    expect(command.reload.execution_context.dig('native_browser_command', 'consumed_at')).to be_present
    expect(JrcProjects::AuditEvent.where(account_id: account_id).group(:action).count).to eq(
      'projects.project.updated' => 1, 'projects.task.updated' => 1
    )
    expect do
      JrcNico::NativeBrowserCommand.execute(account: @fixture_account, user: @fixture_user, request: request) { raise 'Must not replay' }
    end.to raise_error(JrcNico::NativeBrowserCommand::Rejected)
    expect(JrcProjects::AuditEvent.where(account_id: account_id).count).to eq(2)
  end
end

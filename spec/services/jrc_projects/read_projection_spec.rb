require 'rails_helper'

RSpec.describe JrcProjects::ReadProjection do
  let(:account) { create(:account) }
  let(:owner) { create(:user, account: account, role: :agent) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: agent) }
  let(:project) do
    JrcProjects::Project.create!(account: account, owner: owner, key: 'READ', name: 'Read projection', status: 'planned', visibility: 'members')
  end

  before do
    account.enable_features!('jrc_projects')
    member.update!(jrc_projects_enabled: true)
  end

  %w[owner manager member contributor viewer].each do |role|
    it "matches fresh capabilities for a #{role} membership" do
      project.project_members.create!(account: account, user: agent, role: role)
      projection = described_class.new(account_user: member, projects: [project])
      expect(projection.capabilities(project)).to eq(JrcProjects::Authorization.capabilities(member, project))
    end
  end

  it 'matches owner, administrator, account-visible and foreign-account capabilities' do
    admin = create(:user, account: account, role: :administrator).account_users.find_by!(account: account)
    owner_member = account.account_users.find_by!(user: owner)
    owner_member.update!(jrc_projects_enabled: true)
    project.update!(visibility: 'account')
    foreign = create(:account)
    foreign_project = JrcProjects::Project.create!(account: foreign, owner: create(:user, account: foreign), key: 'OTHER', name: 'Other',
                                                   status: 'planned', visibility: 'account')
    [member, owner_member, admin].each do |actor|
      projection = described_class.new(account_user: actor, projects: [project, foreign_project])
      [project, foreign_project].each do |record|
        expect(projection.capabilities(record)).to eq(JrcProjects::Authorization.capabilities(actor, record))
      end
    end
  end

  it 'matches custom role restrictions including a foreign role' do
    project.project_members.create!(account: account, user: agent, role: 'manager')
    role = create(:custom_role, account: account, permissions: %w[jrc_projects_project_view jrc_projects_time_entry_create])
    member.update!(custom_role_id: role.id)
    expect(described_class.new(account_user: member, projects: [project]).capabilities(project))
      .to eq(JrcProjects::Authorization.capabilities(member, project))
    member.update!(custom_role_id: create(:custom_role, account: create(:account), permissions: ['jrc_projects_project_view']).id)
    expect(described_class.new(account_user: member, projects: [project]).capabilities(project)).to eq([])
  end

  it 'reloads revoked membership and disabled account entitlement for every new read' do
    project.project_members.create!(account: account, user: agent, role: 'member')
    expect(described_class.new(account_user: member, projects: [project]).capabilities(project)).not_to be_empty
    AccountUser.find(member.id).update!(jrc_projects_enabled: false)
    expect(described_class.new(account_user: member, projects: [project]).capabilities(project)).to eq([])
    AccountUser.find(member.id).update!(jrc_projects_enabled: true)
    account.disable_features!('jrc_projects')
    expect(described_class.new(account_user: member, projects: [project]).capabilities(project)).to eq([])
    member.destroy!
    expect(described_class.new(account_user: member, projects: [project]).capabilities(project)).to eq([])
  end

  it 'does not replace fresh authorization checks on mutations after a read' do
    project.project_members.create!(account: account, user: agent, role: 'manager')
    expect(described_class.new(account_user: member, projects: [project]).capabilities(project)).to include('projects.project.update')
    AccountUser.find(member.id).update!(jrc_projects_enabled: false)
    expect(JrcProjects::Authorization).not_to be_allowed(account_user: member, capability: 'projects.project.update', project: project)
  end

  it 'preserves company visibility and tenant isolation in the batched directory projection' do
    account.enable_features!('jrc_customer_master')
    company = JrcCustomers::Company.create!(account: account, name: 'Synthetic company')
    project.update!(company_id: company.id)
    projection = described_class.new(account_user: member, projects: [project])
    expect(projection.company(project)).to eq('id' => company.id, 'name' => 'Synthetic company')
    foreign_company = JrcCustomers::Company.create!(account: create(:account), name: 'Foreign company')
    project.company_id = foreign_company.id
    expect(described_class.new(account_user: member, projects: [project]).company(project)).to be_nil
    role = create(:custom_role, account: account, permissions: ['jrc_projects_project_view'])
    member.update!(custom_role_id: role.id)
    expect(described_class.new(account_user: member, projects: [project])).not_to be_directory_access(project)
  end

  describe 'task permission projection' do
    let(:task_operations) { %w[update move delete] }
    let(:task_relations) { [nil, :assignee, :creator] }
    let(:board) { project.boards.create!(account: account, name: 'Synthetic board') }
    let(:column) { board.board_columns.create!(account: account, name: 'Backlog', status_key: 'backlog') }
    let(:task) { project.tasks.create!(account: account, created_by: owner, board_column: column, status: 'backlog', title: 'Synthetic task') }

    %w[owner manager member contributor viewer].each do |role|
      it "preserves #{role} flags and contributor assigned/created restrictions" do
        project.project_members.create!(account: account, user: agent, role: role)
        projection = described_class.new(account_user: member, projects: [project])
        task_relations.each do |relation|
          task.assignee_id = relation == :assignee ? agent.id : nil
          task.created_by_id = relation == :creator ? agent.id : owner.id
          task_operations.each do |operation|
            expected = JrcProjects::Authorization.allowed?(account_user: member, capability: "projects.task.#{operation}", project: project,
                                                           record: task)
            expect(projection.task_permissions(task).fetch("can_#{operation}")).to eq(expected)
          end
        end
      end
    end

    it 'preserves actual owner and custom-role administrator flags' do
      admin = create(:user, account: account, role: :administrator).account_users.find_by!(account: account)
      owner_member = account.account_users.find_by!(user: owner)
      owner_member.update!(jrc_projects_enabled: true)
      role = create(:custom_role, account: account, permissions: %w[jrc_projects_task_view jrc_projects_task_update])
      [owner_member, admin].each do |actor|
        projection = described_class.new(account_user: actor, projects: [project])
        expect(projection.task_permissions(task)).to eq('can_update' => true, 'can_move' => true, 'can_delete' => true)
      end
      admin.update!(custom_role_id: role.id, jrc_projects_enabled: true)
      project.project_members.create!(account: account, user_id: admin.user_id, role: 'member')
      projection = described_class.new(account_user: admin, projects: [project])
      %w[update move delete].each do |operation|
        expected = JrcProjects::Authorization.allowed?(account_user: admin, capability: "projects.task.#{operation}", project: project, record: task)
        expect(projection.task_permissions(task).fetch("can_#{operation}")).to eq(expected)
      end
    end

    it 'keeps actual owner privileges despite a contributor membership on another creators task' do
      project.project_members.create!(account: account, user: owner, role: 'contributor')
      owner_member = account.account_users.find_by!(user: owner)
      owner_member.update!(jrc_projects_enabled: true)
      task.created_by_id = agent.id
      projection = described_class.new(account_user: owner_member, projects: [project])
      expect(projection.task_permissions(task)).to eq('can_update' => true, 'can_move' => true, 'can_delete' => true)
      expect(JrcProjects::Authorization).to be_allowed(account_user: owner_member, capability: 'projects.task.update', project: project, record: task)
    end

    it 'keeps plain administrator privileges despite a contributor membership on another creators task' do
      admin = create(:user, account: account, role: :administrator).account_users.find_by!(account: account)
      project.project_members.create!(account: account, user_id: admin.user_id, role: 'contributor')
      projection = described_class.new(account_user: admin, projects: [project])
      expect(projection.task_permissions(task)).to eq('can_update' => true, 'can_move' => true, 'can_delete' => true)
      expect(JrcProjects::Authorization).to be_allowed(account_user: admin, capability: 'projects.task.update', project: project, record: task)
    end

    it 'denies foreign task/account/project flags and observes revocation on the next read' do
      project.project_members.create!(account: account, user: agent, role: 'contributor')
      task.update!(assignee: agent)
      projection = described_class.new(account_user: member, projects: [project])
      expect(projection.task_permissions(task)).to eq('can_update' => true, 'can_move' => false, 'can_delete' => false)
      task.account_id = create(:account).id
      expect(projection.task_permissions(task).values).to eq([false, false, false])
      task.account_id = account.id
      task.project_id = project.id + 1
      expect(projection.task_permissions(task).values).to eq([false, false, false])
      task.project_id = project.id
      AccountUser.find(member.id).update!(jrc_projects_enabled: false)
      expect(described_class.new(account_user: member, projects: [project]).task_permissions(task).values).to eq([false, false, false])
      expect(JrcProjects::Authorization).not_to be_allowed(account_user: member, capability: 'projects.task.update', project: project, record: task)
    end
  end

  it 'keeps SELECT growth bounded for one, five and twenty-five project cards' do
    projects = Array.new(25) do |index|
      record = JrcProjects::Project.create!(account: account, owner: owner, key: "READ#{index}", name: 'Synthetic', status: 'planned',
                                            visibility: 'members')
      record.project_members.create!(account: account, user: agent, role: 'member')
      record
    end
    warm_records = JrcProjects::Project.where(id: projects.first.id).includes(:owner, :contact).to_a
    warm_projection = described_class.new(account_user: member, projects: warm_records)
    JrcProjects::ProjectSerializer.one(warm_records.first, account_user: member, read_projection: warm_projection)
    measurements = [1, 5, 25].map do |size|
      queries = []
      subscriber = lambda { |*args|
        payload = args.last
        queries << payload[:sql] if payload[:sql].match?(/\ASELECT/i)
      }
      ActiveRecord::Base.uncached do
        ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
          records = JrcProjects::Project.where(id: projects.first(size).map(&:id)).includes(:owner, :contact).to_a
          projection = described_class.new(account_user: member, projects: records)
          counts = JrcProjects::ProjectSerializer.card_counts(account_id: account.id, project_ids: records.map(&:id))
          records.each do |record|
            data = JrcProjects::ProjectSerializer.one(record, account_user: member, read_projection: projection,
                                                              task_counts: { total: 0, completed: 0 }, card_counts: counts.fetch(record.id))
            expect(data.fetch('capabilities')).to eq(JrcProjects::Authorization::WORK)
          end
        end
      end
      queries.size
    end
    warn "project_read_selects sizes=1,5,25 counts=#{measurements.join(',')}"
    expect(measurements.max - measurements.min).to be <= 2
  end
end

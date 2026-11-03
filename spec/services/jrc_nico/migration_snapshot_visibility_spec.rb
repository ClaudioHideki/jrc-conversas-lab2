require 'rails_helper'

RSpec.describe 'NICO persisted evidence and newly registered migration domains' do
  let(:account) { create(:account, custom_attributes: { 'nico_enabled' => true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:access) { JrcNico::OperationalAccess.new(account: account, user: admin).authorize! }
  let(:company) { JrcCustomers::Company.create!(account: account, name: 'Native customer') }
  let(:contact) { create(:contact, account: account, company_id: company.id) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, company: company, owner: admin, status: 'active') }
  let(:context) { JrcRelationship::Context.new(access.membership) }
  let(:snapshot) do
    JrcRelationship::HealthSnapshot.create!(account: account, assignment: assignment, viewer: admin,
      access_signature: context.access_signature, calculated_at: Time.current, fingerprint: SecureRandom.hex(16),
      band: 'healthy', score: 90, config_scope_key: 'account', config_version: 1,
      signals: { '_source_ids' => { 'conversations' => [conversation.id] }, 'health' => { 'score' => 90, 'band' => 'healthy' } })
  end
  let(:project) do
    JrcProjects::Project.create!(account: account, owner: admin, key: 'PENDING', name: 'Project source', status: 'planned', visibility: 'account')
  end

  def pending_mapping(record, domain)
    batch = JrcMigrations::Batch.create!(account: account, created_by: admin, source: 'nico_snapshot', domain: domain, source_digest: 'a' * 64)
    JrcMigrations::Mapping.create!(account: account, batch: batch, source: 'nico_snapshot', domain: domain, legacy_id: record.id.to_s,
      target_id: record.id, source_digest: 'a' * 64, target_digest: 'b' * 64, source_updated_at: Time.current)
  end

  before { account.enable_features!('jrc_relationship', 'jrc_customer_master', 'jrc_crm', 'jrc_projects') }

  it 'rejects a saved health snapshot when an old source became pending outside the current company aggregate' do
    snapshot
    contact.update!(company_id: nil)
    pending_mapping(contact, 'contacts')
    expect do
      JrcNico::DomainAccess.authorize_resource!(access, snapshot.class.name, snapshot.id)
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcRelationship::SnapshotAccess.scope(context, JrcRelationship::HealthSnapshot.all).find(snapshot.id)).to eq(snapshot)
  end

  it 'checks the cached evidence before producing relationship health or WorkContext' do
    snapshot
    contact.update!(company_id: nil)
    pending_mapping(contact, 'contacts')
    expect(JrcRelationship::WorkContext).not_to receive(:new)
    expect do
      JrcNico::DomainActions.new(access).call('read_relationship_customer', { 'assignment_id' => assignment.id })
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'retains a native snapshot whose evidence is still permitted' do
    expect(JrcNico::DomainAccess.authorize_resource!(access, snapshot.class.name, snapshot.id)).to eq(snapshot)
  end

  it 'filters a project by its own migration acceptance before its read DTO' do
    pending_mapping(project, 'projects')
    expect(JrcNico::DomainActions.new(access).call('list_projects', {})[:items]).to be_empty
    expect do
      JrcNico::DomainActions.new(access).call('read_project', { 'project_id' => project.id })
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'filters a task by its own acceptance even when the project is native' do
    task = JrcProjects::Task.create!(account: account, project: project, created_by: admin, title: 'Pending task',
      status: 'backlog', priority: 'medium', estimated_minutes: 0)
    pending_mapping(task, 'project_tasks')
    expect(JrcNico::DomainActions.new(access).call('list_project_tasks', { 'project_id' => project.id })[:items]).to be_empty
    expect do
      JrcNico::DomainActions.new(access).call('read_project_task', { 'project_id' => project.id, 'task_id' => task.id })
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'rechecks the project behind a saved polymorphic audit evidence row' do
    event = JrcProjects::AuditEvent.record!(account: account, actor: admin, action: 'projects.project.created', auditable: project)
    pending_mapping(project, 'projects')
    expect do
      JrcNico::DomainAccess.authorize_resource!(access, event.class.name, event.id)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end
end

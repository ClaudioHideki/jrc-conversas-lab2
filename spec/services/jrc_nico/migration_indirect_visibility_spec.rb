require 'rails_helper'

RSpec.describe 'NICO indirect migration evidence and aggregates' do
  let(:account) { create(:account, custom_attributes: { 'nico_enabled' => true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:access) { JrcNico::OperationalAccess.new(account: account, user: admin).authorize! }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:company) { JrcCustomers::Company.create!(account: account, name: 'Native company') }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, company: company, owner: admin, status: 'active') }
  let(:project) do
    JrcProjects::Project.create!(account: account, owner: admin, contact: contact, key: 'INDIRECT',
      name: 'Native project', status: 'planned', visibility: 'account')
  end
  let(:task) do
    JrcProjects::Task.create!(account: account, project: project, created_by: admin, title: 'Pending task',
      status: 'backlog', priority: 'medium', estimated_minutes: 0, due_on: Date.current)
  end
  let(:risk) do
    JrcRelationship::RiskCase.create!(account: account, assignment: assignment, owner: admin,
      kind: 'engagement', source_key: 'synthetic', reason: 'Historical source', severity: 'high', status: 'detected', plan: {},
      metadata: { '_source_ids' => { 'conversations' => [conversation.id] } })
  end

  before { account.enable_features!('jrc_relationship', 'jrc_customer_master', 'jrc_crm', 'jrc_projects', 'jrc_campaigns') }

  def pending_mapping(record, domain)
    batch = JrcMigrations::Batch.create!(account: account, created_by: admin, source: 'nico_indirect', domain: domain, source_digest: 'a' * 64)
    JrcMigrations::Mapping.create!(account: account, batch: batch, source: 'nico_indirect', domain: domain, legacy_id: record.id.to_s,
      target_id: record.id, source_digest: 'a' * 64, target_digest: 'b' * 64, source_updated_at: Time.current)
  end

  it 'does not count an unaccepted task in a native project card' do
    pending_mapping(task, 'project_tasks')
    result = JrcNico::DomainActions.new(access).call('read_project', { 'project_id' => project.id })
    expect(result[:record].slice('tasks_total', 'tasks_completed', 'progress')).to eq(
      'tasks_total' => 0, 'tasks_completed' => 0, 'progress' => 0)
    expect(JrcProjects::ProjectSerializer.one(project, account_user: access.membership)['tasks_total']).to eq(1)
  end

  it 'omits unaccepted task agenda rows before returning their DTO or manifest' do
    pending_mapping(task, 'project_tasks')
    result = JrcNico::DomainActions.new(access).call('read_operations_agenda', { 'source' => 'projects', 'user_id' => 'all' })
    expect(result[:data]).to be_empty
    expect(result[:resources]).to be_empty
    expect(result[:meta][:returned]).to eq(0)
    expect(JrcOperations::Agenda.new(account_user: access.membership, filters: { source: 'projects', user_id: 'all' }).call[:data].size).to eq(1)
  end

  it 'omits an unaccepted project from related records of a permitted contact' do
    pending_mapping(project, 'projects')
    result = JrcNico::DomainActions.new(access).call('read_operation_links', { 'contact_id' => contact.id })
    expect(result[:projects]).to be_empty
    expect(result[:resources]).not_to include(['JrcProjects::Project', project.id])
  end

  it 'denies a saved operations link whose project acceptance changed' do
    link = JrcOperations::Link.create!(account: account, created_by: admin, project: project, conversation: conversation)
    pending_mapping(project, 'projects')
    expect do
      JrcNico::DomainAccess.authorize_resource!(access, link.class.name, link.id)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'denies historical risk metadata whose source is pending outside the current customer' do
    risk
    pending_mapping(contact, 'contacts')
    expect do
      JrcNico::DomainAccess.authorize_resource!(access, risk.class.name, risk.id)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'rechecks historical relationship metadata before invoking WorkContext' do
    risk
    pending_mapping(contact, 'contacts')
    expect(JrcRelationship::WorkContext).not_to receive(:new)
    expect do
      JrcNico::DomainActions.new(access).call('read_relationship_customer', { 'assignment_id' => assignment.id })
    end.to raise_error(ActiveRecord::RecordNotFound)
  end
end

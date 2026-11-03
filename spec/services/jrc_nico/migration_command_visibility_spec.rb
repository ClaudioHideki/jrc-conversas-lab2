require 'rails_helper'

RSpec.describe 'NICO migration gates at browser preparation and saved campaign history' do
  let(:account) { create(:account, custom_attributes: { 'nico_enabled' => true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:access) { JrcNico::OperationalAccess.new(account: account, user: admin).authorize! }
  let(:contact) { create(:contact, account: account) }
  let(:session) { JrcNico::Session.create!(account: account, user: admin) }
  let(:command) { session.commands.create!(request_id: SecureRandom.uuid, message: 'Synthetic browser boundary') }
  let(:executor) { JrcNico::ToolExecutor.new(access, command: command) }
  let(:campaign) { account.jrc_campaigns.create!(name: 'Synthetic campaign', created_by: admin, audience_type: 'all_contacts') }
  let(:project) do
    JrcProjects::Project.create!(account: account, owner: admin, key: 'COMMAND', name: 'Native project', status: 'planned', visibility: 'account')
  end

  before { account.enable_features!('jrc_campaigns', 'jrc_projects') }

  def pending_mapping(record, domain)
    batch = JrcMigrations::Batch.create!(account: account, created_by: admin, source: 'nico_command', domain: domain, source_digest: 'a' * 64)
    JrcMigrations::Mapping.create!(account: account, batch: batch, source: 'nico_command', domain: domain, legacy_id: record.id.to_s,
      target_id: record.id, source_digest: 'a' * 64, target_digest: 'b' * 64, source_updated_at: Time.current)
  end

  %w[approve_campaign export_campaign].each do |tool|
    it "refuses #{tool} browser preparation for a campaign with an unaccepted recipient" do
      pending_mapping(contact, 'contacts')
      arguments = { 'campaign_id' => campaign.id }
      arguments['digest'] = 'a' * 64 if tool == 'approve_campaign'
      expect { executor.call(tool, arguments) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  it 'refuses a pending parent task before preparing an otherwise permitted native task update' do
    parent = JrcProjects::Task.create!(account: account, project: project, created_by: admin, title: 'Pending parent',
      status: 'backlog', priority: 'medium', estimated_minutes: 0)
    child = JrcProjects::Task.create!(account: account, project: project, created_by: admin, title: 'Native child',
      status: 'backlog', priority: 'medium', estimated_minutes: 0)
    pending_mapping(parent, 'project_tasks')
    expect do
      executor.call('update_project_task', { 'project_id' => project.id, 'task_id' => child.id,
        'lock_version' => child.lock_version, 'parent_id' => parent.id })
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'invalidates saved campaign history after the campaign starts referencing an already pending contact' do
    pending_mapping(contact, 'contacts')
    campaign.update!(audience_type: 'label', audience_config: {})
    operator = JrcNico::OperatorSession.new(account: account, user: admin)
    operator.session.update!(messages: [{ 'role' => 'assistant', 'content' => 'Previously permitted campaign' }],
      context: operator.session.context.merge('resources' => [[campaign.class.name, campaign.id]]))
    digest = JrcNico::OperatorContext.access_digest(access)
    campaign.update!(audience_type: 'all_contacts')
    expect(JrcNico::OperatorContext.access_digest(access)).to eq(digest)
    refreshed = JrcNico::OperatorSession.new(account: account, user: admin)
    expect(refreshed.session.messages).to be_empty
  end
end

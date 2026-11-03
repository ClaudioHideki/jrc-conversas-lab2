require 'rails_helper'

RSpec.describe 'Migration project relationships stay within the destination account' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:foreign_account) { create(:account) }
  let(:foreign_user) { create(:user, account: foreign_account, role: :administrator) }
  let(:foreign_project) { JrcProjects::Project.create!(account: foreign_account, owner: foreign_user, key: 'FOREIGN', name: 'Foreign project') }
  let(:project) { JrcProjects::Project.create!(account: account, owner: admin, key: 'LOCAL', name: 'Local project') }
  let(:dates) { { 'created_at' => '2021-01-02T12:00:00Z', 'updated_at' => '2024-02-03T12:00:00Z' } }
  let(:project_data) do
    dates.merge('key' => 'IMPORT', 'name' => 'Imported', 'owner_id' => admin.id, 'status' => 'planned', 'visibility' => 'account')
  end
  let(:task_data) do
    dates.merge('project_id' => project.id, 'created_by_id' => admin.id, 'title' => 'Imported task',
                'status' => 'backlog', 'priority' => 'medium', 'estimated_minutes' => 0)
  end

  %w[owner_id accepted_by_id].each do |field|
    it "rejects a foreign project #{field} on an otherwise valid source" do
      adapter = JrcMigrations::Adapters::Project.new(account: account, source: 'tenant_fixture')
      expect(adapter.build(project_data)).to be_valid
      expect { adapter.build(project_data.merge(field => foreign_user.id)) }
        .to raise_error(JrcMigrations::Error, 'INVALID_DESTINATION')
    end
  end

  it 'rejects a foreign contact on an otherwise valid project' do
    adapter = JrcMigrations::Adapters::Project.new(account: account, source: 'tenant_fixture')
    foreign_contact = create(:contact, account: foreign_account)
    expect { adapter.build(project_data.merge('contact_id' => foreign_contact.id)) }
      .to raise_error(JrcMigrations::Error, 'INVALID_DESTINATION')
  end

  it 'rejects a foreign project and creator on otherwise valid tasks before any write' do
    adapter = JrcMigrations::Adapters::ProjectTask.new(account: account, source: 'tenant_fixture')
    expect(adapter.build(task_data)).to be_valid
    expect { adapter.build(task_data.merge('project_id' => foreign_project.id)) }
      .to raise_error(JrcMigrations::Error, 'INVALID_DESTINATION')
    expect { adapter.build(task_data.merge('created_by_id' => foreign_user.id)) }
      .to raise_error(JrcMigrations::Error, 'INVALID_DESTINATION')
  end
end

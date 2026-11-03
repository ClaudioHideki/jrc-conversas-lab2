require 'rails_helper'
require 'base64'

# These committed fixtures are shared by two connections and explicitly cleaned up on failure.
# rubocop:disable RSpec/InstanceVariable
RSpec.describe JrcMigrations::Execute, :sd_concurrency do
  self.use_transactional_tests = false
  include JrcServiceDeskConcurrency

  before do
    @account = create(:account)
    @admin = create(:user, account: @account, role: :administrator)
    @project = JrcProjects::Project.create!(account: @account, owner: @admin, key: 'IMPORT_RACE', name: 'Original project')
    bytes = 'Synthetic imported text'
    row = { 'legacy_id' => 'race-file', 'project_id' => @project.id, 'filename' => 'history.txt', 'content_type' => 'text/plain',
            'file_base64' => Base64.strict_encode64(bytes), 'file_sha256' => Digest::SHA256.hexdigest(bytes), 'file_size' => bytes.bytesize,
            'created_at' => '2021-01-02T12:00:00Z', 'updated_at' => '2021-01-02T12:00:00Z' }
    @batch = JrcMigrations::Stage.new(account: @account, user: @admin).call(source: 'locking_fixture', domain: 'project_attachments', rows: [row],
                                                                            mapping: {})
    JrcMigrations::Preview.new(batch: @batch, user: @admin).call
  end

  after do
    @project&.attachments&.each(&:purge)
    JrcMigrations::Mapping.where(account: @account).delete_all
    JrcMigrations::Item.where(account: @account).delete_all
    JrcMigrations::Batch.where(account: @account).delete_all # Only this example's batch and its cascading event history.
    JrcProjects::AuditEvent.where(account: @account).delete_all
    @project&.reload&.destroy!
    @account&.destroy!
    @admin&.destroy!
  end

  it 'allows native audit FK reads while serializing the import and the project mutation' do
    project_locked = Queue.new
    account_locked = Queue.new
    executor = described_class.new(batch: @batch, user: @admin)
    allow(executor).to receive(:mapping_for).and_wrap_original do |original, item|
      account_locked << true # Execute holds its real Account lock before looking up the destination.
      original.call(item)
    end
    account_id = @account.id
    user_id = @admin.id
    project_id = @project.id
    database_deadlocks = Queue.new
    observer = TracePoint.new(:raise) do |event|
      error = event.raised_exception
      database_deadlocks << "#{error.class}: #{error.message}" if error.is_a?(ActiveRecord::Deadlocked) || error.is_a?(PG::TRDeadlockDetected)
    end
    outcomes = observer.enable(target_thread: nil) do
      concurrently([
                     lambda do
                       project = JrcProjects::Project.find(project_id)
                       project.with_lock do
                         ActiveRecord::Base.connection.execute("SET LOCAL statement_timeout='10s'")
                         project_locked << true
                         Timeout.timeout(10) { account_locked.pop }
                         before = project.attributes
                         project.update!(name: 'Human project edit')
                         JrcProjects::AuditEvent.record!(account: Account.find(account_id), actor: User.find(user_id),
                                                         action: 'projects.project.updated', auditable: project,
                                                         before_data: before, after_data: project.attributes)
                       end
                       :human_committed
                     end,
                     lambda do
                       Timeout.timeout(10) { project_locked.pop }
                       executor.call
                       :import_committed
                     end
                   ])
    end
    descriptions = outcomes.map { |result| result.is_a?(Exception) ? "#{result.class}: #{result.message.lines.first}" : result }
    expect(descriptions).to contain_exactly(:human_committed, :import_committed)
    deadlocks = Array.new(database_deadlocks.size) { database_deadlocks.pop }
    expect(deadlocks).to be_empty, deadlocks.join("\n")
    expect(@project.reload.name).to eq('Human project edit')
    expect(@batch.items.reload.sole.status).to eq('applied')
    expect(@project.attachments_attachments.sole.blob.download).to eq('Synthetic imported text')
    expect(JrcProjects::AuditEvent.where(account_id: account_id, action: 'projects.project.updated').count).to eq(1)
  end
end
# rubocop:enable RSpec/InstanceVariable

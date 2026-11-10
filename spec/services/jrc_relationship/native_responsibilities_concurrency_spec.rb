require 'rails_helper'
require 'timeout'

RSpec.describe JrcRelationship::NativeResponsibilities do
  self.use_transactional_tests = false

  before do
    unless Rails.env.test? && ActiveRecord::Base.connection.select_value('SELECT current_database()') == 'jrc_rel_v2_candidate_test'
      raise 'Use only the owned isolated relationship candidate database'
    end
  end

  it 'refuses a preview while its native project writer holds the parent lock, without persisting a proposal' do
    account = create(:account)
    account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm', 'jrc_projects')
    actor = create(:user, account: account, role: :administrator)
    target = create(:user, account: account, role: :administrator)
    member = account.account_users.find_by!(user: actor)
    contact = create(:contact, account: account)
    assignment = JrcRelationship::Assignment.create!(account: account, owner: actor, contact: contact)
    project = JrcProjects::Projects::Create.call(account: account, actor: actor, attributes: { name: 'Native editor race', contact_id: contact.id },
                                                 idempotency_key: SecureRandom.uuid)
    task = JrcProjects::Tasks::Create.call(account_user: member, project: project,
                                           attributes: { title: 'Pending source task', assignee_id: actor.id }, correlation_id: 'editor-race')
    JrcRelationship::SuccessPlan.create!(account: account, assignment: assignment, owner: actor, title: 'Pending editor source',
                                         goals: [{ 'metric' => 'Delivery', 'task_id' => task.id }])
    ready = Queue.new
    release = Queue.new
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        JrcProjects::Project.find(project.id).with_lock do
          ready << true
          release.pop
        end
      end
    end
    Timeout.timeout(30) { ready.pop }
    service = JrcRelationship::ReviewedPortfolioBatch.new(JrcRelationship::Context.new(member))
    input = { 'ids' => [assignment.id], 'operation' => 'assign', 'owner_id' => target.id,
              'transfer_responsibilities' => true, 'justification' => 'Synthetic editor contention', 'request_id' => SecureRandom.uuid }
    expect { service.preview(input) }.to raise_error(ActiveRecord::LockWaitTimeout)
    expect(JrcRelationship::BatchReview.where(account: account)).not_to exist
    expect(task.reload.assignee_id).to eq(actor.id)
  ensure
    release << true if release
    worker&.join(30)
    worker&.kill if worker&.alive?
    worker&.join
  end

  it 'executes one of two competing frozen task transfers and leaves the other visibly stale' do
    account = create(:account)
    account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm', 'jrc_projects')
    actor = create(:user, account: account, role: :administrator)
    targets = create_list(:user, 2, account: account, role: :administrator)
    member = account.account_users.find_by!(user: actor)
    context = JrcRelationship::Context.new(member)
    contact = create(:contact, account: account)
    assignment = JrcRelationship::Assignment.create!(account: account, owner: actor, contact: contact)
    project = JrcProjects::Projects::Create.call(account: account, actor: actor, attributes: { name: 'Synthetic race', contact_id: contact.id },
                                                 idempotency_key: SecureRandom.uuid)
    targets.each { |user| JrcProjects::ProjectMember.create!(account: account, project: project, user: user, role: 'member') }
    task = JrcProjects::Tasks::Create.call(account_user: member, project: project,
                                           attributes: { title: 'Synthetic competing task', assignee_id: actor.id }, correlation_id: 'race-create')
    JrcRelationship::SuccessPlan.create!(account: account, assignment: assignment, owner: actor, title: 'Pending native task',
                                         goals: [{ 'metric' => 'Delivery', 'task_id' => task.id }])
    service = JrcRelationship::ReviewedPortfolioBatch.new(context)
    reviews = targets.map do |user|
      input = { 'ids' => [assignment.id], 'operation' => 'assign', 'owner_id' => user.id,
                'transfer_responsibilities' => true, 'justification' => 'Synthetic competing proposal', 'request_id' => SecureRandom.uuid }
      proposal = service.preview(input)
      service.approve(proposal.fetch('id'), digest: proposal.fetch('digest'))
      proposal.fetch('id')
    end
    gate = Queue.new
    results = Queue.new
    workers = reviews.map do |id|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          current = JrcRelationship::Context.new(account.account_users.find_by!(user: actor))
          results << JrcRelationship::ReviewedPortfolioBatch.new(current).advance(id).fetch('state')
        rescue StandardError => e
          results << e.class.name
        end
      end
    end
    2.times { gate << true }
    Timeout.timeout(30) { workers.each(&:join) }
    expect(Array.new(2) { results.pop }).to contain_exactly('completed', 'attention')
    expect(task.reload.assignee_id).to eq(assignment.reload.owner_id)
    expect(JrcProjects::AuditEvent.where(auditable_type: task.class.name, auditable_id: task.id, action: 'projects.task.updated').count).to eq(1)
  ensure
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end
end

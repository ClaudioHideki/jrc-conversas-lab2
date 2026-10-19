require 'rails_helper'
require 'timeout'

RSpec.describe 'Reviewed batch and cadence concurrency' do
  self.use_transactional_tests = false
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:member) { admin.account_users.find_by!(account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, contact: contact, owner: admin) }
  let(:input) { { 'ids' => [assignment.id], 'operation' => 'assign', 'owner_id' => nil, 'request_id' => SecureRandom.uuid } }

  before do
    databases = %w[jrc_jornada_candidate_test jrc_nico_broker_candidate_test]
    unless Rails.env.test? && ENV['JRC_REVIEWED_CONCURRENCY'] == '1' && databases.include?(ENV['POSTGRES_DATABASE'])
      raise 'Use only the explicitly enabled disposable candidate database'
    end
    account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    admin
    member
    assignment
  end

  # Fixtures are committed in the dedicated disposable database so independent
  # PostgreSQL connections can exercise the real row/advisory locks.
  def race
    gate = Queue.new
    results = Queue.new
    workers = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          results << yield
        rescue StandardError => e
          results << e
        end
      end
    end
    2.times { gate << true }
    Timeout.timeout(30) { workers.each(&:join) }
    Array.new(2) { results.pop }
  ensure
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end

  it 'admits the same request once and returns the same frozen review to two connections' do
    params = input
    results = race do
      context = JrcRelationship::Context.new(AccountUser.find(member.id))
      JrcRelationship::ReviewedPortfolioBatch.new(context).preview(params)
    end
    expect(results).to all(be_a(Hash))
    expect(results.map { |result| result.fetch('id') }.uniq.size).to eq(1)
    expect(JrcRelationship::BatchReview.where(account: account).count).to eq(1)
    expect(assignment.reload.owner_id).to eq(admin.id)
  end

  it 'fences removal of a current inbox membership until the native operation transaction completes' do
    operator = create(:user, account: account, role: :agent)
    assignment.update!(owner: operator)
    inbox = create(:inbox, account: account)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
    membership = InboxMember.create!(inbox: inbox, user: operator)
    entered = Queue.new
    release = Queue.new
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        JrcRelationship::BatchReview.transaction do
          JrcRelationship::BatchReviewAuthority.new(account_id: account.id, actor_id: operator.id).call do |context|
            expect(ConversationPolicy.new(context.to_h, conversation).show?).to be(true)
            entered << true
            release.pop
            JrcRelationship::Workflow.new(context).activity!(assignment: assignment, title: 'Authorized under inbox fence',
                                                            due_at: Time.current, request_id: SecureRandom.uuid)
          end
        end
      end
    end
    Timeout.timeout(30) { entered.pop }
    expect do
      InboxMember.transaction do
        ActiveRecord::Base.connection.execute("SET LOCAL lock_timeout='150ms'")
        InboxMember.where(id: membership.id).delete_all
      end
    end.to raise_error(ActiveRecord::LockWaitTimeout)
    expect(InboxMember.exists?(membership.id)).to be(true)
    release << true
    Timeout.timeout(30) { worker.join }
    expect(JrcCrm::Activity.where(account: account).pluck(:title)).to eq(['Authorized under inbox fence'])
  ensure
    release << true if release
    Timeout.timeout(30) { worker&.join }
    worker&.kill if worker&.alive?
  end

  it 'serializes two due workers without creating the native activity twice' do
    conversation = create(:conversation, account: account, inbox: create(:inbox, account: account), contact: contact)
    book = JrcRelationship::Playbook.create!(account: account, name: 'Concurrent native cadence', active: true, trigger_kind: 'no_contact',
                                            steps: [{ 'kind' => 'activity', 'title' => 'One concurrent activity', 'after_days' => 0 }])
    context = JrcRelationship::Context.new(member)
    service = JrcRelationship::ReviewedPortfolioBatch.new(context)
    preview = service.preview(input.merge('operation' => 'cadence', 'playbook_id' => book.id,
                                          'conversation_id' => conversation.display_id, 'starts_at' => Time.current.iso8601(6)))
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    result = service.advance(preview.fetch('id'))
    id = result.fetch('items').first.fetch('receipt').fetch('cadence_id')
    results = race do
      fresh = JrcRelationship::Context.new(AccountUser.find(member.id))
      JrcRelationship::ReviewedCadence.new(fresh).advance(id)
    end
    expect(results).to all(include('state' => 'completed'))
    expect(JrcCrm::Activity.where(account: account).count).to eq(1)
    expect(JrcRelationship::CadenceStep.where(cadence_enrollment_id: id).pluck(:state)).to eq(['applied'])
  end

  it 'lets an already locked native item commit before cancellation and cancels all subsequent items' do
    conversation = create(:conversation, account: account, inbox: create(:inbox, account: account), contact: contact)
    book = JrcRelationship::Playbook.create!(account: account, name: 'Cancelable cadence', active: true, trigger_kind: 'no_contact',
                                            steps: [{ 'kind' => 'activity', 'title' => 'Committed before cancel', 'after_days' => 0 },
                                                    { 'kind' => 'activity', 'title' => 'Canceled next task', 'after_days' => 1 }])
    service = JrcRelationship::ReviewedPortfolioBatch.new(JrcRelationship::Context.new(member))
    preview = service.preview(input.merge('operation' => 'cadence', 'playbook_id' => book.id,
                                          'conversation_id' => conversation.display_id, 'starts_at' => Time.current.iso8601(6)))
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    id = service.advance(preview.fetch('id')).fetch('items').first.fetch('receipt').fetch('cadence_id')
    entered = Queue.new
    release = Queue.new
    results = Queue.new
    allow_any_instance_of(JrcRelationship::Playbooks).to receive(:apply_scheduled_step!).and_wrap_original do |method, **args|
      result = method.call(**args)
      entered << true
      release.pop
      result
    end
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        results << JrcRelationship::ReviewedCadence.new(JrcRelationship::Context.new(AccountUser.find(member.id))).advance(id)
      end
    end
    Timeout.timeout(30) { entered.pop }
    canceler = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        results << JrcRelationship::ReviewedCadence.new(JrcRelationship::Context.new(AccountUser.find(member.id))).cancel(id)
      end
    end
    release << true
    Timeout.timeout(30) { [worker, canceler].each(&:join) }
    expect(Array.new(2) { results.pop }).to all(be_a(Hash))
    record = JrcRelationship::CadenceEnrollment.find(id)
    expect(record.state).to eq('stopped')
    expect(record.steps.order(:ordinal).pluck(:state)).to eq(%w[applied canceled])
    expect(JrcCrm::Activity.where(account: account).pluck(:title)).to eq(['Committed before cancel'])
  ensure
    release << true if release
    [worker, canceler].compact.each { |thread| thread.kill if thread.alive? }
    [worker, canceler].compact.each(&:join)
  end
end

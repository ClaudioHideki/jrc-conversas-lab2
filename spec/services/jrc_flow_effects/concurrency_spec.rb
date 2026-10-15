require 'rails_helper'

RSpec.describe JrcFlowEffects::Apply, :sd_concurrency do # rubocop:disable RSpec/SpecFilePathFormat -- Isolated SQL concurrency suite.
  self.use_transactional_tests = false
  include JrcServiceDeskConcurrency

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account).reload }
  let(:input) do
    { 'organization_id' => SecureRandom.uuid, 'operation_id' => SecureRandom.uuid, 'dispatch_proof' => SecureRandom.uuid,
      'inbox_id' => conversation.inbox_id.to_s, 'remote_contact_id' => conversation.contact_id.to_s,
      'expected_control_revision' => conversation.reload.attributes.fetch('jrc_effect_control_revision', 0).to_s,
      'operation' => 'note', 'value_json' => '"Atomic note"' }
  end

  def apply(input)
    JrcFlowEffects::Apply.new(account: account, user: user, access_token: user.access_token)
                         .call(conversation.display_id, input)
  end

  def wait_for_row_lock(pid)
    Timeout.timeout(10) do
      loop do
        break if ActiveRecord::Base.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}") == 'Lock'

        sleep 0.01
      end
    end
  end

  def worker
    ready = Queue.new
    outcome = Queue.new
    thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        ready << connection.select_value('SELECT pg_backend_pid()')
        outcome << yield
      rescue StandardError => e
        outcome << e
      end
    end
    [thread, ready.pop, outcome]
  end

  it 'serializes a human message on the exact Conversation row, including rollback' do
    operator = user
    conversation
    old_revision = conversation.attributes.fetch('jrc_effect_control_revision', 0)
    thread = outcome = nil
    Conversation.transaction do
      conversation.lock!
      thread, pid, outcome = worker do
        Message.transaction do
          Messages::MessageBuilder.new(operator, Conversation.find(conversation.id), content: 'Human', private: true).perform
          raise ActiveRecord::Rollback
        end
        :rolled_back
      end
      wait_for_row_lock(pid)
      expect(conversation.reload.attributes.fetch('jrc_effect_control_revision', 0)).to eq(old_revision)
    end
    Timeout.timeout(10) { thread.join }
    expect(outcome.pop).to eq(:rolled_back)
    expect(conversation.reload.attributes.fetch('jrc_effect_control_revision', 0)).to eq(old_revision)
  ensure
    cleanup_concurrent_workers([thread].compact)
  end

  it 'linearizes an effect before an already waiting source update without a ContactInbox lock inversion' do
    params = input
    user.access_token
    original_source = conversation.contact_inbox.source_id
    receipt = nil
    thread = outcome = nil
    Conversation.transaction do
      conversation.lock!
      thread, pid, outcome = worker do
        ContactInbox.where(id: conversation.contact_inbox_id).update_all(source_id: SecureRandom.uuid) # rubocop:disable Rails/SkipsModelValidations -- Prove SQL paths bypassing callbacks retain the guard.
      end
      wait_for_row_lock(pid)
      receipt = apply(params)
      expect(receipt.routing_source_hash).to eq(Digest::SHA256.hexdigest(original_source))
    end
    Timeout.timeout(10) { thread.join }
    expect(outcome.pop).to eq(1)
    expect(conversation.reload.jrc_effect_control_revision).to be > receipt.control_revision_after
  ensure
    cleanup_concurrent_workers([thread].compact)
  end

  it 'rejects an effect waiting behind a committed human assignment and permits no message' do
    params = input
    operator = user
    operator.access_token
    thread = outcome = nil
    count = conversation.messages.count
    Conversation.transaction do
      conversation.update_column(:assignee_id, operator.id) # rubocop:disable Rails/SkipsModelValidations -- Prove SQL paths bypassing callbacks retain the guard.
      thread, pid, outcome = worker { apply(params) }
      wait_for_row_lock(pid)
    end
    Timeout.timeout(10) { thread.join }
    expect(outcome.pop).to be_a(ArgumentError)
    expect(conversation.messages.count).to eq(count)
  ensure
    cleanup_concurrent_workers([thread].compact)
  end

  it 'commits exactly one message and receipt for two simultaneous retries' do
    params = input
    user.access_token
    result = concurrently([-> { apply(params).id }, -> { apply(params).id }])
    expect(result.uniq.size).to eq(1)
    expect(result.first).to be_a(Integer)
    expect(Message.where(conversation: conversation, private: true, content: 'Atomic note').count).to eq(1)
  end
end

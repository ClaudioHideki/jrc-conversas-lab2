require 'rails_helper'
require 'timeout'

RSpec.describe 'Quick reply and catalog independent connections', type: :model, approval_core: true do
  self.use_transactional_tests = false

  # Only two owned threads, committed synthetic rows and a disposable CI database.
  def simultaneous(&block)
    ready, start, results = Queue.new, Queue.new, Queue.new
    threads = 2.times.map do
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do |connection|
          ready << connection.select_value('SELECT pg_backend_pid()')
          start.pop
          begin
            results << [:ok, block.call]
          rescue StandardError => error
            results << [:error, error.class.name, error.message]
          end
        end
      end
    end
    Timeout.timeout(20) do
      expect(2.times.map { ready.pop }.uniq.size).to eq(2)
      2.times { start << true }
      threads.each(&:join)
      2.times.map { results.pop }
    end
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
  end

  it 'creates exactly one native message for concurrent identical delivery intents' do
    account = create(:account)
    actor = create(:user, account: account, role: :administrator)
    conversation = create(:conversation, account: account).reload
    response = create(:canned_response, account: account, content: 'Synthetic concurrent text')
    revision = response.updated_at.iso8601(6)
    results = simultaneous do
      CannedResponses::Delivery.new(response: CannedResponse.find(response.id), conversation: Conversation.find(conversation.id), user: actor).call(
        content: 'Synthetic concurrent text', key: 'synthetic-concurrent-delivery', expected_actor_id: actor.id, confirmed: true, revision: revision
      ).id
    end
    expect(results.map(&:first)).to eq(%i[ok ok]), results.inspect
    expect(results.map(&:last).uniq.size).to eq(1)
    expect(conversation.messages.outgoing.where(content: 'Synthetic concurrent text').count).to eq(1)
  end

  it 'imports the same catalog once with one committed batch audit' do
    scope = approval_scope
    author = approval_actor(scope)
    values = { document: { schema_version: '1.0', activate: false, people: [], approval_rules: [{ code: 'SYNTHETIC_CONCURRENT_V1',
               module: 'Synthetic', title: 'Synthetic concurrent rule', enabled: false, workflow_state: 'draft', approver_user_ids: [], self_approval_allowed: false }] }.to_json,
               format: 'json', mappings: { 'SYNTHETIC_CONCURRENT_V1' => 'synthetic.review' }, people_mappings: {},
               company_id: scope[:company].id, unit_id: scope[:unit].id }
    service = JrcApprovals::CatalogImport.new(account: scope[:account], user: author.user)
    preview = service.call(**values)
    results = simultaneous do
      JrcApprovals::CatalogImport.new(account: scope[:account], user: author.user).call(**values, dry_run: false,
        confirmed: true, key: 'synthetic-concurrent-import', expected_digest: preview['plan_digest'])['rows'].first['policy_id']
    end
    expect(results.map(&:first)).to eq(%i[ok ok]), results.inspect
    expect(results.map(&:last).uniq.size).to eq(1)
    expect(JrcApprovals::Policy.where(account_id: scope[:account].id).count).to eq(1)
    expect(JrcApprovals::AuditEvent.where(account_id: scope[:account].id, event_type: 'catalog_imported').count).to eq(1)
  end
end

require 'rails_helper'
require 'timeout'

RSpec.describe 'Commercial gates with independent PostgreSQL connections', type: :model,
  approval_core: true, commercial_approvals: true do
  self.use_transactional_tests = false

  def simultaneous(&block)
    ready, start, results = Queue.new, Queue.new, Queue.new
    threads = 2.times.map do |index|
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do |connection|
          ready << connection.select_value('SELECT pg_backend_pid()')
          start.pop
          begin
            results << [:ok, block.call(index)]
          rescue StandardError => error
            results << [:error, error.class.name, error.message]
          end
        end
      end
    end
    Timeout.timeout(30) do
      pids = 2.times.map { ready.pop }
      expect(pids.uniq.length).to eq(2)
      puts "E3 PostgreSQL independent connections: #{pids.join(',')}"
      2.times { start << true }
      threads.each(&:join)
      2.times.map { results.pop }
    end
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
  end

  def concurrent_fixture
    scope = approval_scope
    author = approval_actor(scope, permissions: JrcApprovals::Authorization::PERMISSIONS + ['jrc_crm'], role: :administrator)
    approver = approval_actor(scope, permissions: ['jrc_approvals_decide', 'jrc_crm'])
    [scope, author, approver, commercial_fixture(scope, author)[:proposal]]
  end

  it 'replays two simultaneous commercial request creations with one ledger entry' do
    scope, author, approver, proposal = concurrent_fixture
    commercial_policy(scope, author, [approver])
    results = simultaneous { commercial_request(scope, author, proposal, idempotency_key: 'concurrent').first.id }
    expect(results.map(&:first)).to eq(%i[ok ok])
    expect(results.map(&:last).uniq.length).to eq(1)
    expect(JrcApprovals::Request.where(account: scope[:account]).count).to eq(1)
    expect(JrcApprovals::AuditEvent.where(account: scope[:account], event_type: 'request_created').count).to eq(1)
  end

  it 'serializes two commercial decisions and refuses the stale optimistic version' do
    scope, author, approver, proposal = concurrent_fixture
    other = approval_actor(scope, permissions: ['jrc_approvals_decide', 'jrc_crm'])
    commercial_policy(scope, author, [approver, other])
    request = commercial_request(scope, author, proposal).first
    results = simultaneous do |index|
      approval_vote(scope, [approver, other][index], JrcApprovals::Request.find(request.id), expected_version: 0,
        idempotency_key: "concurrent-#{index}").id
    end
    expect(results.count { |result| result.first == :ok }).to eq(1)
    expect(results.select { |result| result.first == :error }.first).to eq([:error, 'JrcApprovals::Error', 'VERSION_CONFLICT'])
    expect(request.reload.decisions.count).to eq(1)
  end

  it 'serializes repeated delivery with one real message, PDF attachment and send event' do
    scope, author, _, proposal = concurrent_fixture
    proposal.update!(approval_status: 'approved')
    create(:conversation, account: scope[:account], contact: proposal.customer_contact)
    results = simultaneous do
      JrcCrm::ProposalDeliveryService.new(proposal: JrcCrm::Proposal.find(proposal.id), actor: author.user,
        base_url: 'https://synthetic.invalid', idempotency_key: 'delivery').call[:message].id
    end
    expect(results.map(&:first)).to eq(%i[ok ok]), results.inspect
    expect(results.map(&:last).uniq.length).to eq(1)
    expect(proposal.events.where(event_type: 'sent').count).to eq(1)
    expect(Message.where(account: scope[:account]).count).to eq(1)
    message = Message.find(results.first.last)
    expect(message.attachments.count).to eq(1)
    expect(message.attachments.first.file.download).to start_with('%PDF-')
  end

  it 'serializes two conversions into one native order and one native operational approval' do
    scope, author, approver, proposal = concurrent_fixture
    proposal.update!(approval_status: 'approved')
    create(:conversation, account: scope[:account], contact: proposal.customer_contact)
    JrcCrm::ProposalDeliveryService.new(proposal: proposal, actor: author.user, base_url: 'https://synthetic.invalid').call
    proposal.accept_by_customer!(name: 'Synthetic signer', document: 'synthetic', remote_ip: '127.0.0.1', user_agent: 'test')
    commercial_policy(scope, author, [approver], key: 'crm.proposal_convert')
    commercial_mode(scope[:account], 'crm.proposal_convert', 'enforcement')
    request = commercial_request(scope, author, proposal, key: 'crm.proposal_convert').first
    approval_vote(scope, approver, request)
    results = simultaneous { JrcCrm::ProposalToOrderService.new(proposal: JrcCrm::Proposal.find(proposal.id), actor: author.user).call.id }
    expect(results.map(&:first)).to eq(%i[ok ok]), results.inspect
    expect(results.map(&:last).uniq.length).to eq(1)
    expect(proposal.sales_orders.count).to eq(1)
    expect(proposal.sales_orders.first.backoffice_requests.where(request_kind: 'approval').count).to eq(1)
  end

  it 'serializes concurrent relevant edits and invalidation without deleting or duplicating approval history' do
    scope, author, approver, proposal = concurrent_fixture
    commercial_policy(scope, author, [approver])
    request = commercial_request(scope, author, proposal).first
    approval_vote(scope, approver, request)
    results = simultaneous do |index|
      source = JrcCrm::Proposal.find(proposal.id)
      source.with_lock do
        source.proposal_items.first.update!(quantity: index + 2)
        JrcApprovals::CommercialInvalidation.call(resource: source.reload, user: author.user)
      end
      true
    end
    expect(results.map(&:first)).to eq(%i[ok ok]), results.inspect
    expect(request.reload.state).to eq('stale')
    expect(request.decisions.count).to eq(1)
    expect(JrcApprovals::AuditEvent.where(request_id: request.id, event_type: 'request_invalidate').count).to eq(1)
  end
end

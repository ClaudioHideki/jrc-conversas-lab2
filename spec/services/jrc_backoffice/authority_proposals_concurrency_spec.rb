require 'rails_helper'
require 'timeout'

RSpec.describe JrcBackoffice::AuthorityProposals, :approval_core, :authority_core do
  self.use_transactional_tests = false

  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:domain) { authority_domain(account, actor) }
  let(:reviewer) { approval_actor(domain, permissions: %w[jrc_crm jrc_approvals_decide]) }
  let(:document) { authority_document(domain) }
  let(:roster) { authority_roster(domain) }
  let(:version) do
    document
    roster
    domain[:versions].create!(idempotency_key: SecureRandom.uuid, expected_source_digest: domain[:versions].source_digest(domain[:contract].id),
                              change_reason: 'TESTE SINTÉTICO — Concorrência de poderes.')
  end
  let(:input) { authority_input(version, roster, document) }

  before do
    config = ActiveRecord::Base.connection_db_config
    raise 'Dedicated owned concurrency database required' unless Rails.env.test? && config.database == 'jrc_four_domains_schema_authority_test' &&
                                                                 config.host == 'jrc-rel-v2-pg-20261101'

    domain
    authority_policy(domain, [reviewer])
    input
  end

  def concurrent_authority(inputs)
    ready = Queue.new
    start = Queue.new
    results = Queue.new
    threads = inputs.map do |attributes|
      authority_thread(ready, start, results) { yield attributes }
    end
    Timeout.timeout(45) do
      expect(Array.new(2) { ready.pop }.uniq.length).to eq(2)
      2.times { start << true }
      threads.each(&:join)
      Array.new(2) { results.pop }
    end
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
  end

  def authority_thread(ready, start, results)
    Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        ready << connection.select_value('SELECT pg_backend_pid()')
        start.pop
        results << yield
      rescue StandardError => e
        results << e
      end
    end
  end

  it 'serializes the same intent into one proposal and native request using independent PostgreSQL connections' do
    results = concurrent_authority([input, input]) do |attributes|
      described_class.new(account: Account.find(account.id), actor: User.find(actor.id), request_id: domain[:operation].id).create!(**attributes).id
    end
    expect(results).to all(be_a(Integer)), results.inspect
    expect(results.uniq.length).to eq(1)
    expect(JrcBackoffice::AuthorityProposal.where(account_id: account.id).count).to eq(1)
    expect(JrcApprovals::Request.where(account_id: account.id).count).to eq(1)
    expect(account.jrc_crm_audit_events.where(event_type: 'backoffice_authority_proposed').count).to eq(1)
  end

  it 'rejects a competing revision without losing evidence or creating a second pending case' do
    results = concurrent_authority([input, input.merge(idempotency_key: SecureRandom.uuid)]) do |attributes|
      described_class.new(account: Account.find(account.id), actor: User.find(actor.id), request_id: domain[:operation].id).create!(**attributes).id
    end
    expect(results.count { |row| row.is_a?(Integer) }).to eq(1)
    expect(results.reject { |row| row.is_a?(Integer) }.map { |row| row.class.name }).to eq(['JrcBackoffice::AuthorityProposals::Changed'])
    expect(JrcBackoffice::AuthorityProposal.where(account_id: account.id).pluck(:revision)).to eq([1])
    expect(JrcApprovals::Request.where(account_id: account.id).count).to eq(1)
  end

  it 'preserves the native concurrent vote guard with one decision and no duplicate legal approval' do
    proposal = described_class.new(account: account, actor: actor, request_id: domain[:operation].id).create!(**input)
    request = JrcApprovals::Request.find_by!(account_id: account.id, resource_type: proposal.class.name, resource_id: proposal.id)
    decision = { request_id: request.id, step_code: 'review', decision: 'approved', reason: 'TESTE SINTÉTICO — Decisão concorrente.',
                 expected_version: request.lock_version, idempotency_key: SecureRandom.uuid }
    results = concurrent_authority([decision, decision.merge(idempotency_key: SecureRandom.uuid)]) do |attributes|
      JrcApprovals::Decisions.new(account: Account.find(account.id), user: User.find(reviewer.user_id)).call(**attributes).id
    end
    expect(results.count { |row| row.is_a?(Integer) }).to eq(1)
    expect(results.reject { |row| row.is_a?(Integer) }.map(&:code)).to eq(['VERSION_CONFLICT'])
    expect(request.reload.decisions.count).to eq(1)
    expect(JrcBackoffice::AuthorityStatus.new(proposal: proposal, actor: actor).call(verify: true)[:status]).to eq('verified')
    expect(domain[:contract].reload.signature_status).to eq('not_started')
  end
end

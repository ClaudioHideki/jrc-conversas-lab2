# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

RSpec.describe 'Initial recording customer-link transaction contention', :pabx do
  self.use_transactional_tests = false
  include_context 'with native authorized quality review source'

  let(:contact) { create(:contact, account: account, company: company, name: 'SYNTHETIC explicit initial contact') }
  let(:state) { { ready: Queue.new, results: Queue.new } }
  let(:input) do
    { 'contact_id' => contact.id.to_s, 'call_session_id' => source_call.id.to_s,
      'call_id' => record.external_unique_id, 'lock_version' => source_call.reload.lock_version, 'confirm' => true }
  end

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned disposable recording contact-link database required' unless owned && !ApplicationRecord.connection.transaction_open?

    example.run
  end

  before do
    account.enable_features!('jrc_customer_master')
    role.update!(permissions: role.permissions + %w[jrc_contact_center_operate contact_manage])
  end

  def writer
    JrcContactCenter::RecordingCustomerLink.new(account: account, member: member)
  end

  def link_audits
    Audited.audit_class.where(associated: account, comment: JrcContactCenter::RecordingCustomerLink::COMMENT)
  end

  def link_worker
    values = input.deep_dup
    identifiers = [account.id, member.id, record.id]
    ready, results = state.values_at(:ready, :results)
    Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        ready << connection.raw_connection.backend_pid
        handler = JrcContactCenter::RecordingCustomerLink.new(account: Account.find(identifiers[0]), member: AccountUser.find(identifiers[1]))
        results << handler.call(identifiers[2], values)
      end
    rescue StandardError => e
      results << e
    end
  end

  def wait_for_source_lock
    pid = Timeout.timeout(8) { state[:ready].pop }
    query = <<~SQL.squish
      WITH RECURSIVE blockers(pid) AS (
        SELECT unnest(pg_blocking_pids(#{Integer(pid)})) UNION
        SELECT next_blocker.pid FROM blockers
          CROSS JOIN LATERAL unnest(pg_blocking_pids(blockers.pid)) AS next_blocker(pid)
          WHERE blockers.pid <> pg_backend_pid() AND blockers.pid > 0
      ) SELECT EXISTS (SELECT 1 FROM blockers WHERE pid = pg_backend_pid())
    SQL
    Timeout.timeout(8) { sleep 0.02 until ApplicationRecord.connection.select_value(query) == true }
    pid
  end

  def join_workers(workers)
    workers.each do |worker|
      worker.join(20)
      raise 'Owned native customer-link contender remained active' if worker.alive?
    end
  end

  it 'proves two actual waiting backends, one initial link and one audit without overwriting an existing result' do
    input
    workers = []
    pids = []
    begin
      account.with_lock do
        2.times do
          workers << link_worker
          pids << wait_for_source_lock
        end
      end
    ensure
      join_workers(workers)
    end
    results = Array.new(2) { Timeout.timeout(8) { state[:results].pop } }
    successes, failures = results.partition { |value| value.is_a?(Hash) }
    expect(pids.uniq.length).to eq(2)
    expect(successes.size).to eq(1)
    expect(failures).to contain_exactly(be_a(JrcContactCenter::OperationError))
    expect(source_call.reload.contact_id).to eq(contact.id)
    expect(link_audits.count).to eq(1)
  end

  it 'revalidates the current operator right after waiting on the actual account lock' do
    input
    workers = []
    begin
      account.with_lock do
        workers << link_worker
        wait_for_source_lock
        role.update!(permissions: role.permissions - ['jrc_contact_center_operate'])
      end
    ensure
      join_workers(workers)
    end
    result = Timeout.timeout(8) { state[:results].pop }
    expect(result).to be_a(Pundit::NotAuthorizedError)
    expect(source_call.reload.contact_id).to be_nil
    expect(link_audits).to be_empty
  end

  it 'rolls back the actual native link when its audit cannot persist and permits a later explicit retry' do
    values = input
    connection = ApplicationRecord.connection
    table = Audited.audit_class.table_name
    name = "cc_synthetic_contact_link_#{Integer(account.id)}"
    begin
      comment = connection.quote(JrcContactCenter::RecordingCustomerLink::COMMENT)
      condition = "comment IS NULL OR comment <> #{comment} OR associated_id <> #{Integer(account.id)}"
      connection.add_check_constraint(table, condition, name: name)
      installed = true
      expect { writer.call(record.id, values) }.to raise_error(ActiveRecord::StatementInvalid)
      expect(source_call.reload.contact_id).to be_nil
      expect(link_audits).to be_empty
    ensure
      connection.remove_check_constraint(table, name: name) if installed
    end
    receipt = writer.call(record.id, values)
    expect(receipt.fetch(:contact_id)).to eq(contact.id.to_s)
    expect(link_audits.count).to eq(1)
  end
end

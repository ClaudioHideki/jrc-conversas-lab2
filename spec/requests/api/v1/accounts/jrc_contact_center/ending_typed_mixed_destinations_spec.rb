require 'rails_helper'
require 'timeout'

# Future native mixed-destination proof only. Direct synthetic configuration is
# not public editor, queue delivery, UI or external-provider acceptance.
RSpec.describe 'Independent native CRM and Service Desk ending results' do
  self.use_transactional_tests = false

  include_context 'with native typed ending schema evidence'
  include_context 'with native ending attempt operators'
  include_context 'JRC Service Desk domain'

  let(:operator) { attempt_operator }
  let(:customer) { account.master_companies.create!(name: 'SYNTHETIC independent destination customer') }
  let(:contact) { create(:contact, account: account, company_id: customer.id, name: 'SYNTHETIC independent destination requester') }
  let(:sd_account) { account }
  let(:sd_user) { operator.user }
  let(:sd_account_user) { operator }
  let(:sd_contact) { contact }
  let(:typed_mode) { 'automatic' }
  let(:mixed_fault) { { installed: false, observed: false } }
  let(:typed_version) { publish_typed_schema_definition('actions' => mixed_actions) }
  let(:mixed_crm_action) { { 'kind' => 'crm', 'parameters' => {} } }
  let(:mixed_actions) do
    [mixed_crm_action,
     { 'kind' => 'service_desk', 'parameters' => {
       'unit_id' => sd_unit.id.to_s, 'service_id' => nil,
       'attributes' => { 'title' => 'SYNTHETIC independent native ticket',
                         'description' => 'SYNTHETIC independent native ticket description',
                         'status_id' => sd_status.id.to_s, 'priority_id' => sd_priority.id.to_s }
     } }]
  end
  let(:typed_origin) do
    call = new_origin_source_call
    call.update!(contact_id: contact.id, company_id: customer.id)
    JrcContactCenter::CallLeg.create!(account: account, call_session: call, account_user: operator, queue: queue,
                                    direction: 'inbound', status: 'connected', started_at: call.started_at, answered_at: call.answered_at)
    call.update!(status: 'ended', ended_at: Time.current)
    row = JrcContactCenter::Qualification.find_by!(account: account, account_user: operator, call_session: call)
    JrcContactCenter::QualificationManager.new(account: account, member: operator).complete!(
      row, { reason_code: 'SYNTHETIC_ORIGIN_REASON', outcome_code: 'completed' }
    )
    JrcContactCenter::EndingActionOrigin.find_by!(account: account, source_qualification_id: row.id)
  end

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Exclusive committed native mixed destination database required' unless owned
    raise 'Independent mixed destination transactions required' if ApplicationRecord.connection.transaction_open?

    example.run
  end

  before do
    account.enable_features!('jrc_crm', 'jrc_customer_master')
    operator.update!(crm_enabled: true)
    business.update!(settings: business.settings.merge('service_desk_unit_id' => sd_unit.id.to_s))
  end

  after do
    stop_mixed_sd_rejection if mixed_fault[:installed]
  end

  def mixed_attempt(kind, retry_of: nil, actor_member: operator)
    attributes = { account: account, origin: typed_origin, readiness: typed_readiness,
                   rule_code: 'SYNTHETIC_ORIGIN_RULE', destination_kind: kind, request_key: SecureRandom.uuid }
    if retry_of
      attributes.merge!(retry_of: retry_of, retry_requested_by_account_user_id: actor_member.id)
    end
    JrcContactCenter::EndingDestinationAttempt.create!(**attributes).reload
  end

  def run_mixed(row)
    observer = lambda do |*arguments|
      exception = arguments.last[:exception]
      mixed_fault[:observed] = true if exception && exception.last.to_s.include?(mixed_rejection_marker)
    end
    ActiveSupport::Notifications.subscribed(observer, 'sql.active_record') do
      JrcContactCenter::EndingActions::ExecuteDestinationAttempt.new(account: account, attempt_id: row.id).call
    end
  end

  def mixed_rejection_marker
    "SYNTHETIC_PRIVATE_SD_RECEIPT_REJECTION_#{Integer(account.id)}"
  end

  def mixed_native_counts
    [account.jrc_crm_leads.where(contact: contact).count,
     JrcServiceDesk::Ticket.where(account: account, requester: contact).count,
     JrcContactCenter::EndingDestinationExecution.where(account: account).count,
     JrcContactCenter::EndingDestinationOutcome.where(account: account).count]
  end

  def mixed_worker(row, state)
    ids = [account.id, row.id]
    Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        state[:ready] << connection.raw_connection.backend_pid
        command = JrcContactCenter::EndingActions::ExecuteDestinationAttempt.new(account: Account.find(ids.first), attempt_id: ids.last)
        state[:results] << command.call
      end
    rescue StandardError => e
      state[:results] << e
    end
  end

  def wait_for_mixed_lock(state)
    pid = Timeout.timeout(8) { state[:ready].pop }
    query = mixed_owned_lock_sql(pid)
    Timeout.timeout(8) do
      ApplicationRecord.connection.uncached { sleep 0.02 until ApplicationRecord.connection.select_value(query) == true }
    end
    pid
  end

  def mixed_owned_lock_sql(pid)
    # A later contender may wait behind another worker before the owned lock.
    # UNION visits each live blocker once, including when the graph has a cycle.
    <<~SQL.squish
      WITH RECURSIVE blockers(pid) AS (
        SELECT unnest(pg_blocking_pids(#{Integer(pid)}))
        UNION
        SELECT next_blocker.pid FROM blockers
        CROSS JOIN LATERAL unnest(pg_blocking_pids(blockers.pid)) AS next_blocker(pid)
        WHERE blockers.pid <> pg_backend_pid() AND blockers.pid > 0
      )
      SELECT EXISTS (SELECT 1 FROM blockers WHERE pid = pg_backend_pid())
    SQL
  end

  def join_mixed_workers(workers)
    workers.each do |worker|
      worker.join(20)
      raise 'Synthetic mixed destination worker remained active' if worker.alive?
    end
  end

  # The injected PostgreSQL rejection is local to this owned synthetic account.
  # Native ticket creation, events, permissions, transactions and receipts run.
  def reject_mixed_sd_receipt
    name = "cc_mixed_sd_receipt_#{Integer(account.id)}"
    ApplicationRecord.connection.execute(<<~SQL.squish)
      CREATE FUNCTION pg_temp.#{name}() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NEW.account_id = #{Integer(account.id)} AND NEW.destination_kind = 'service_desk' THEN
          RAISE EXCEPTION '#{mixed_rejection_marker}';
        END IF;
        RETURN NEW;
      END; $$;
      CREATE TRIGGER #{name} BEFORE INSERT ON jrc_contact_center_ending_destination_executions
        FOR EACH ROW EXECUTE FUNCTION pg_temp.#{name}();
    SQL
    mixed_fault[:installed] = true
  end

  def stop_mixed_sd_rejection
    name = "cc_mixed_sd_receipt_#{Integer(account.id)}"
    ApplicationRecord.connection.execute("DROP TRIGGER #{name} ON jrc_contact_center_ending_destination_executions")
    ApplicationRecord.connection.execute("DROP FUNCTION pg_temp.#{name}()")
    mixed_fault[:installed] = false
  end

  it 'commits independent native CRM and Service Desk successes as the exact original nonadministrator' do
    crm = mixed_attempt('crm')
    sd = mixed_attempt('service_desk')
    expect([run_mixed(crm), run_mixed(sd)]).to all(have_attributes(outcome: 'succeeded', result_code: 'completed'))
    expect(mixed_native_counts).to eq([1, 1, 2, 2])
    expect([crm.reload.execution.target_type, sd.reload.execution.target_type]).to eq(%w[JrcCrm::Lead JrcServiceDesk::Ticket])
    expect(account.jrc_crm_leads.where(contact: contact).sole.owner_id).to eq(operator.user_id)
    expect(operator.reload.administrator?).to be false
    expect(JrcServiceDesk::Ticket.where(account: account, requester: contact).sole.created_by_membership_id).to eq(sd_membership.id)
    expect(JrcContactCenter::EndingActionExecution.where(account: account)).to be_empty
  end

  it 'acknowledges repeated delivery without recreating either native effect or receipt' do
    rows = [mixed_attempt('crm'), mixed_attempt('service_desk')]
    results = rows.map { |row| run_mixed(row).attributes }
    expect(rows.map { |row| run_mixed(row).attributes }).to eq(results)
    expect(rows.map { |row| run_mixed(row).attributes }).to eq(results)
    expect(mixed_native_counts).to eq([1, 1, 2, 2])
  end

  %w[crm service_desk].each do |destination|
    it "serializes actual duplicate #{destination} deliveries on separate PostgreSQL backends" do
      row = mixed_attempt(destination)
      states = Array.new(2) { { ready: Queue.new, results: Queue.new } }
      workers, pids = [], []
      begin
        account.with_lock do
          ApplicationRecord.connection.select_values('SELECT pid FROM pg_stat_activity')
          observer = ApplicationRecord.connection.raw_connection.backend_pid
          expect(ApplicationRecord.connection.select_value(mixed_owned_lock_sql(observer))).to be(false)
          states.each do |state|
            workers << mixed_worker(row, state)
            pids << wait_for_mixed_lock(state)
          end
        end
      ensure
        join_mixed_workers(workers)
      end
      results = states.map { |state| Timeout.timeout(8) { state[:results].pop } }
      expect(results).to all(be_a(JrcContactCenter::EndingDestinationOutcome))
      expect(results.map(&:outcome)).to eq(%w[succeeded succeeded])
      expect(results.map(&:id).uniq.length).to eq(1)
      expect(pids.uniq.length).to eq(2)
      expect(pids).not_to include(ApplicationRecord.connection.raw_connection.backend_pid)
      expected = destination == 'crm' ? [1, 0, 1, 1] : [0, 1, 1, 1]
      expect(mixed_native_counts).to eq(expected)
    end
  end

  it 'preserves CRM success when a real PostgreSQL rejection rolls back the Service Desk effect and native events' do
    crm = mixed_attempt('crm')
    sd = mixed_attempt('service_desk')
    succeeded = run_mixed(crm).attributes
    reject_mixed_sd_receipt
    expect(run_mixed(sd)).to have_attributes(outcome: 'failed', result_code: 'destination_failure', execution_id: nil)
    expect(mixed_fault[:observed]).to be true
    expect(crm.reload.outcome.attributes).to eq(succeeded)
    expect(mixed_native_counts).to eq([1, 0, 1, 2])
    expect(JrcServiceDesk::TicketEvent.where(account: account)).to be_empty
    expect(sd.reload.outcome.attributes.values.join(' ')).not_to include('SYNTHETIC_PRIVATE_SD_RECEIPT_REJECTION')
  end

  it 'retries only the explicitly selected failed Service Desk predecessor with the same effect key' do
    crm = mixed_attempt('crm')
    first = mixed_attempt('service_desk')
    crm_result = run_mixed(crm).attributes
    reject_mixed_sd_receipt
    expect([run_mixed(first).outcome, mixed_fault[:observed]]).to eq(['failed', true])
    stop_mixed_sd_rejection
    retry_row = mixed_attempt('service_desk', retry_of: first)
    expect([retry_row.effect_key, retry_row.request_key == first.request_key]).to eq([first.effect_key, false])
    expect(run_mixed(retry_row).outcome).to eq('succeeded')
    expect(mixed_native_counts).to eq([1, 1, 2, 3])
    expect(crm.reload.outcome.attributes).to eq(crm_result)
    expect([first.reload.outcome.outcome, run_mixed(first).outcome]).to eq(%w[failed failed])
    expect(JrcServiceDesk::Ticket.where(account: account, requester: contact).sole.idempotency_key).to eq(first.effect_key)
  end

  it 'never creates a retry for an already successful CRM sibling' do
    crm = mixed_attempt('crm')
    expect(run_mixed(crm).outcome).to eq('succeeded')
    expect { mixed_attempt('crm', retry_of: crm) }.to raise_error(ActiveRecord::StatementInvalid, /already succeeded/)
    expect(mixed_native_counts).to eq([1, 0, 1, 1])
  end

  it 'revalidates current native unit membership on a selected retry while preserving the CRM receipt' do
    crm = mixed_attempt('crm')
    first = mixed_attempt('service_desk')
    crm_result = run_mixed(crm).attributes
    reject_mixed_sd_receipt
    expect(run_mixed(first).outcome).to eq('failed')
    expect(mixed_fault[:observed]).to be true
    stop_mixed_sd_rejection
    retry_row = mixed_attempt('service_desk', retry_of: first)
    sd_membership.update!(active: false)
    expect(run_mixed(retry_row)).to have_attributes(outcome: 'blocked', result_code: 'reference_unavailable', execution_id: nil)
    expect(crm.reload.outcome.attributes).to eq(crm_result)
    expect(mixed_native_counts).to eq([1, 0, 1, 3])
  end

  it 'does not authorize another member to review the original agents unsuccessful destination' do
    first = mixed_attempt('service_desk')
    reject_mixed_sd_receipt
    expect(run_mixed(first).outcome).to eq('failed')
    expect(mixed_fault[:observed]).to be true
    expect { mixed_attempt('service_desk', retry_of: first, actor_member: member) }
      .to raise_error(ActiveRecord::StatementInvalid, /original-agent review/)
    expect(mixed_native_counts).to eq([0, 0, 0, 1])
  end

  it 'keeps old unfinished destinations permanently blocked after disabling and reactivating their rule' do
    crm = mixed_attempt('crm')
    pending = mixed_attempt('service_desk')
    crm_result = run_mixed(crm).attributes
    publish_typed_schema_definition('active' => false)
    publish_typed_schema_definition('active' => true)
    expect(run_mixed(pending)).to have_attributes(outcome: 'blocked', result_code: 'deactivated', execution_id: nil)
    expect(crm.reload.outcome.attributes).to eq(crm_result)
    expect(mixed_native_counts).to eq([1, 0, 1, 2])
    expect { mixed_attempt('service_desk', retry_of: pending) }
      .to raise_error(ActiveRecord::StatementInvalid, /permanently blocked by deactivation/)
  end
end

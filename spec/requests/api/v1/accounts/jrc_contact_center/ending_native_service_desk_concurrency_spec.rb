require 'rails_helper'
require 'timeout'

# Real PostgreSQL workers and native Ticket/event services. No provider calls,
# substitute permissions, fake persistence or shared Redis queue operations.
RSpec.describe 'Native Service Desk ending adapter under original authority contention' do
  self.use_transactional_tests = false

  include_context 'with native ending execution original evidence'
  include_context 'with native ending attempt operators'
  include_context 'JRC Service Desk domain'

  let(:operator) { attempt_operator }
  let(:customer) { account.master_companies.create!(name: 'SYNTHETIC concurrent SD customer') }
  let(:contact) { create(:contact, account: account, company_id: customer.id) }
  let(:sd_account) { account }
  let(:sd_user) { operator.user }
  let(:sd_account_user) { operator }
  let(:sd_contact) { contact }
  let(:request_key) { SecureRandom.uuid }
  let(:parameters) do
    { 'unit_id' => sd_unit.id.to_s, 'service_id' => nil,
      'attributes' => { 'title' => 'SYNTHETIC concurrent native ticket', 'status_id' => sd_status.id.to_s,
                        'priority_id' => sd_priority.id.to_s } }
  end
  let(:reference) do
    call = new_origin_source_call
    call.update!(contact_id: contact.id, company_id: customer.id)
    JrcContactCenter::CallLeg.create!(account: account, call_session: call, account_user: operator, queue: queue,
                                      direction: 'inbound', status: 'connected', started_at: call.started_at, answered_at: call.answered_at)
    call.update!(status: 'ended', ended_at: Time.current)
    qualification = JrcContactCenter::Qualification.find_by!(account: account, call_session: call, account_user: operator)
    JrcContactCenter::EndingActionOrigin.find_by!(account: account, source_qualification_id: qualification.id)
  end

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned native Service Desk contention database required' unless owned
    raise 'Committed native Service Desk fixtures required' if ApplicationRecord.connection.transaction_open?

    example.run
  end

  before do
    @native_sd_workers = []
    account.enable_features!('jrc_customer_master')
    business.update!(settings: business.settings.merge('service_desk_unit_id' => sd_unit.id.to_s))
    reference
    parameters
    request_key
  end

  after do
    join_native_sd_workers
  end

  def native_sd_worker(state)
    ids = [account.id, reference.id, request_key]
    input = parameters.deep_dup
    worker = Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        state[:ready] << connection.raw_connection.backend_pid
        owner = Account.find(ids.first)
        context = JrcContactCenter::EndingActions::OriginalActorContext.new(account: owner, origin_id: ids.second)
        result = context.call do |member, origin|
          JrcContactCenter::EndingActions::ServiceDeskTicketDestination.new(account: owner, member: member).call(
            origin: origin, parameters: input, request_key: ids.last
          )
        end
        state[:results] << result
      end
    rescue StandardError => e
      state[:results] << e
    end
    @native_sd_workers << worker
  end

  def wait_for_native_sd_lock(state)
    pid = Timeout.timeout(8) { state[:ready].pop }
    sql = "SELECT count(*) FROM pg_stat_activity WHERE pid=#{Integer(pid)} AND wait_event_type='Lock'"
    Timeout.timeout(8) do
      ApplicationRecord.connection.uncached { sleep 0.02 until ApplicationRecord.connection.select_value(sql).to_i == 1 }
    end
    pid
  end

  def join_native_sd_workers
    @native_sd_workers.each do |worker|
      worker.join(20)
      raise 'Synthetic native Service Desk worker remained active' if worker.alive?
    end
  end

  it 'creates only one native Ticket and creation context for duplicate deliveries on two PostgreSQL backends' do
    state = { ready: Queue.new, results: Queue.new }
    pids = []
    account.with_lock('FOR NO KEY UPDATE') do
      2.times do
        native_sd_worker(state)
        pids << wait_for_native_sd_lock(state)
      end
    end
    join_native_sd_workers
    results = 2.times.map { Timeout.timeout(8) { state[:results].pop } }
    expect(results).to all(be_a(JrcServiceDesk::Ticket))
    expect(results.map(&:id).uniq.length).to eq(1)
    expect(pids.uniq.length).to eq(2)
    expect(pids).not_to include(ApplicationRecord.connection.raw_connection.backend_pid)
    expect(JrcServiceDesk::Ticket.where(account: account).count).to eq(1)
    expect(JrcServiceDesk::TicketEvent.where(account: account, event_type: 'ticket_created').count).to eq(1)
    expect(JrcServiceDesk::TicketEvent.where(account: account, event_type: 'creation_context_recorded').count).to eq(1)
  end

  it 'revalidates native unit membership after waiting for an authority writer' do
    state = { ready: Queue.new, results: Queue.new }
    account.with_lock('FOR NO KEY UPDATE') do
      native_sd_worker(state)
      wait_for_native_sd_lock(state)
      sd_membership.update!(active: false)
    end
    join_native_sd_workers
    result = Timeout.timeout(8) { state[:results].pop }
    expect(result.class.name).to eq('ActiveRecord::RecordNotFound')
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
    expect(JrcServiceDesk::TicketEvent.where(account: account)).to be_empty
  end

  it 'refuses a changed native business-unit mapping even when both units remain authorized' do
    create(:jrc_sd_membership, unit: sd_other_unit, account_user: operator)
    state = { ready: Queue.new, results: Queue.new }
    account.with_lock('FOR NO KEY UPDATE') do
      native_sd_worker(state)
      wait_for_native_sd_lock(state)
      business.update!(settings: business.settings.merge('service_desk_unit_id' => sd_other_unit.id.to_s))
    end
    join_native_sd_workers
    result = Timeout.timeout(8) { state[:results].pop }
    expect(result.class.name).to eq('JrcContactCenter::OperationError')
    expect(result.code).to eq('ending_service_desk_mapping_changed')
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
    expect(JrcServiceDesk::TicketEvent.where(account: account)).to be_empty
  end

  it 'revalidates the exact original company after an actual Contact edit lock wait' do
    other = account.master_companies.create!(name: 'SYNTHETIC moved concurrent SD customer')
    state = { ready: Queue.new, results: Queue.new }
    contact.with_lock do
      native_sd_worker(state)
      wait_for_native_sd_lock(state)
      contact.update!(company_id: other.id)
    end
    join_native_sd_workers
    result = Timeout.timeout(8) { state[:results].pop }
    expect(result.class.name).to eq('JrcContactCenter::OperationError')
    expect(result.code).to eq('ending_customer_reference_changed')
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
    expect(JrcServiceDesk::TicketEvent.where(account: account)).to be_empty
  end

  it 'does not borrow native administrator defaults after ticket-create authority is revoked' do
    permissions = %w[contact_manage jrc_contact_center_view jrc_contact_center_operate jrc_service_desk_module_view]
    role = create(:custom_role, account: account, permissions: permissions)
    account.enable_features!('custom_roles')
    state = { ready: Queue.new, results: Queue.new }
    account.with_lock('FOR NO KEY UPDATE') do
      native_sd_worker(state)
      wait_for_native_sd_lock(state)
      operator.update!(custom_role: role)
    end
    join_native_sd_workers
    result = Timeout.timeout(8) { state[:results].pop }
    expect(result.class.name).to eq('Pundit::NotAuthorizedError')
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
    expect(JrcServiceDesk::TicketEvent.where(account: account)).to be_empty
  end

  it 'revalidates the native account Service Desk feature after actual account-row contention' do
    state = { ready: Queue.new, results: Queue.new }
    account.with_lock('FOR NO KEY UPDATE') do
      native_sd_worker(state)
      wait_for_native_sd_lock(state)
      account.disable_features!('jrc_service_desk')
    end
    join_native_sd_workers
    result = Timeout.timeout(8) { state[:results].pop }
    expect(result.class.name).to eq('ActiveRecord::RecordNotFound')
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
    expect(JrcServiceDesk::TicketEvent.where(account: account)).to be_empty
  end
end

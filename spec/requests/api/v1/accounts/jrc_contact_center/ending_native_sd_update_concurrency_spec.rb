require 'rails_helper'
require 'timeout'

# Committed synthetic data, actual PostgreSQL waits and native commands only.
RSpec.describe 'Linked Service Desk update after real original-authority contention' do
  self.use_transactional_tests = false

  include_context 'with native ending execution original evidence'
  include_context 'with native ending attempt operators'
  include_context 'JRC Service Desk domain'

  let(:operator) { attempt_operator }
  let(:contact) { create(:contact, account: account, company_id: issuer.id, name: 'SYNTHETIC concurrent linked update') }
  let(:sd_account) { account }
  let(:sd_user) { operator.user }
  let(:sd_account_user) { operator }
  let(:sd_contact) { contact }
  let(:parameters) do
    { 'ticket_id' => ticket.id.to_s, 'expected_lock_version' => ticket.lock_version,
      'attributes' => { 'title' => 'SYNTHETIC next linked update' } }
  end
  let(:reference) do
    call = new_origin_source_call
    call.update!(contact_id: contact.id, company_id: issuer.id)
    JrcContactCenter::CallLeg.create!(account: account, call_session: call, account_user: operator, queue: queue,
                                      direction: 'inbound', status: 'connected', started_at: call.started_at, answered_at: call.answered_at)
    call.update!(status: 'ended', ended_at: Time.current)
    qualification = JrcContactCenter::Qualification.find_by!(account: account, call_session: call, account_user: operator)
    JrcContactCenter::EndingActionOrigin.find_by!(account: account, source_qualification_id: qualification.id)
  end
  let(:ticket) do
    JrcContactCenter::EndingActions::OriginalActorContext.new(account: account, origin_id: reference.id).call do |member, origin|
      JrcContactCenter::EndingActions::ServiceDeskTicketDestination.new(account: account, member: member).call(
        origin: origin, request_key: SecureRandom.uuid,
        parameters: { 'unit_id' => sd_unit.id.to_s, 'service_id' => nil,
                      'attributes' => { 'title' => 'SYNTHETIC initial update target',
                                        'description' => 'SYNTHETIC committed native update target description',
                                        'status_id' => sd_status.id.to_s, 'priority_id' => sd_priority.id.to_s } }
      )
    end
  end

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned native linked-ticket concurrency database required' unless owned && !ApplicationRecord.connection.transaction_open?

    example.run
  end

  before do
    account.enable_features!('jrc_customer_master')
    business.update!(settings: business.settings.merge('service_desk_unit_id' => sd_unit.id.to_s))
    input = { 'ticket_id' => ticket.id.to_s, 'expected_lock_version' => ticket.lock_version,
              'attributes' => { 'title' => 'SYNTHETIC committed update baseline' } }
    native_original_update(account.id, reference.id, input)
    ticket.reload
  end

  def native_original_update(account_id, origin_id, input)
    owner = Account.find(account_id)
    JrcContactCenter::EndingActions::OriginalActorContext.new(account: owner, origin_id: origin_id).call do |member, origin|
      JrcContactCenter::EndingActions::ServiceDeskTicketUpdate.new(account: owner, member: member).call(origin: origin, parameters: input)
    end
  end

  def linked_update_worker(state)
    args = [account.id, reference.id, parameters.deep_dup]
    Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        state[:ready] << connection.raw_connection.backend_pid
        state[:results] << native_original_update(*args)
      end
    rescue StandardError => e
      state[:results] << e
    end
  end

  def wait_for_linked_update_lock(state)
    pid = Timeout.timeout(8) { state[:ready].pop }
    sql = "SELECT count(*) FROM pg_stat_activity WHERE pid=#{Integer(pid)} AND wait_event_type='Lock'"
    Timeout.timeout(8) do
      ApplicationRecord.connection.uncached { sleep 0.02 until ApplicationRecord.connection.select_value(sql).to_i == 1 }
    end
    pid
  end

  def linked_update_result(worker, state)
    worker.join(20)
    raise 'Synthetic linked-ticket update worker remained active' if worker.alive?

    Timeout.timeout(8) { state[:results].pop }
  end

  it 'refuses the original agents revoked operational membership after an actual lock wait' do
    state = { ready: Queue.new, results: Queue.new }
    worker = nil
    account.with_lock('FOR NO KEY UPDATE') do
      worker = linked_update_worker(state)
      pid = wait_for_linked_update_lock(state)
      expect(pid).not_to eq(ApplicationRecord.connection.raw_connection.backend_pid)
      sd_membership.update!(active: false)
    end
    result = linked_update_result(worker, state)
    expect(result.class.name).to eq('ActiveRecord::RecordNotFound')
    expect(ticket.reload.title).to eq('SYNTHETIC committed update baseline')
    expect(ticket.ticket_events.where(event_type: 'ticket_updated').count).to eq(1)
    expect(JrcServiceDesk::Ticket.where(account: account).count).to eq(1)
  end

  it 'refuses a disabled native module after contention without undoing the positive baseline' do
    state = { ready: Queue.new, results: Queue.new }
    worker = nil
    account.with_lock('FOR NO KEY UPDATE') do
      worker = linked_update_worker(state)
      wait_for_linked_update_lock(state)
      account.disable_features!('jrc_service_desk')
    end
    result = linked_update_result(worker, state)
    expect(result.class.name).to eq('Pundit::NotAuthorizedError')
    expect(ticket.reload.title).to eq('SYNTHETIC committed update baseline')
    expect(ticket.ticket_events.where(event_type: 'ticket_updated').count).to eq(1)
    expect(JrcContactCenter::EndingActionExecution.where(account: account)).to be_empty
  end

  it 'does not use the customer identity observed before another transaction changed it' do
    other = account.master_companies.create!(name: 'SYNTHETIC denied concurrent update customer')
    state = { ready: Queue.new, results: Queue.new }
    worker = nil
    account.with_lock('FOR NO KEY UPDATE') do
      worker = linked_update_worker(state)
      wait_for_linked_update_lock(state)
      contact.update!(company_id: other.id)
    end
    result = linked_update_result(worker, state)
    expect(result.class.name).to eq('JrcContactCenter::OperationError')
    expect(result.code).to eq('ending_customer_reference_changed')
    expect(ticket.reload.title).to eq('SYNTHETIC committed update baseline')
    expect(ticket.ticket_events.where(event_type: 'ticket_updated').count).to eq(1)
  end
end

require 'rails_helper'
require 'timeout'

# Committed fixtures, native writes and actual PostgreSQL workers. These cases
# must run separately in the owned corporate database, never ordinary core.
RSpec.describe 'Native CRM activity with current original authority after real contention' do
  self.use_transactional_tests = false

  include_context 'with native ending execution original evidence'
  include_context 'with native ending attempt operators'

  let(:operator) { attempt_operator }
  let(:contact) { create(:contact, account: account, company_id: issuer.id, name: 'SYNTHETIC concurrent activity contact') }
  let(:parameters) { { 'activity_type' => 'call', 'title' => 'SYNTHETIC original contact', 'description' => 'SYNTHETIC explicit result' } }
  let(:reference) do
    call = new_origin_source_call
    call.update!(contact_id: contact.id, company_id: issuer.id)
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
    raise 'Owned CRM activity concurrency database required' unless owned && !ApplicationRecord.connection.transaction_open?

    example.run
  end

  before do
    account.enable_features!('jrc_crm', 'jrc_customer_master')
    operator.update!(crm_enabled: true)
    reference
    # A real positive operation proves the same source was initially permitted.
    native_original_activity(account.id, reference.id)
  end

  def native_original_activity(account_id, origin_id)
    owner = Account.find(account_id)
    JrcContactCenter::EndingActions::OriginalActorContext.new(account: owner, origin_id: origin_id).call do |member, origin|
      call = JrcContactCenter::CallSession.where(account: owner).find(origin.call_session_id)
      JrcContactCenter::EndingActions::CrmActivityDestination.new(account: owner, member: member).call(
        origin: origin, parameters: parameters, trigger_at: call.ended_at
      )
    end
  end

  def native_activity_worker(state)
    ids = [account.id, reference.id]
    Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        state[:ready] << connection.raw_connection.backend_pid
        state[:results] << native_original_activity(*ids)
      end
    rescue StandardError => e
      state[:results] << e
    end
  end

  def wait_for_native_activity_lock(state)
    pid = Timeout.timeout(8) { state[:ready].pop }
    sql = "SELECT count(*) FROM pg_stat_activity WHERE pid=#{Integer(pid)} AND wait_event_type='Lock'"
    Timeout.timeout(8) do
      ApplicationRecord.connection.uncached { sleep 0.02 until ApplicationRecord.connection.select_value(sql).to_i == 1 }
    end
    pid
  end

  def joined_native_activity_result(worker, state)
    worker.join(20)
    raise 'Synthetic native activity worker remained active' if worker.alive?

    Timeout.timeout(8) { state[:results].pop }
  end

  it 'refuses a newly revoked CRM flag after actual account contention without repeating the positive baseline' do
    state = { ready: Queue.new, results: Queue.new }
    worker = nil
    account.with_lock('FOR NO KEY UPDATE') do
      worker = native_activity_worker(state)
      pid = wait_for_native_activity_lock(state)
      expect(pid).not_to eq(ApplicationRecord.connection.raw_connection.backend_pid)
      operator.update!(crm_enabled: false)
    end
    result = joined_native_activity_result(worker, state)
    expect(result.class.name).to eq('Pundit::NotAuthorizedError')
    expect(account.jrc_crm_activities.where(contact: contact).count).to eq(1)
    expect(account.jrc_crm_leads.where(contact: contact).count).to eq(1)
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'activity_created').count).to eq(1)
    expect(JrcContactCenter::EndingActionExecution.where(account: account)).to be_empty
  end

  it 'refuses changed source unit coverage while retaining the already committed native activity and audit' do
    other = JrcCrm::BusinessUnit.create!(account: account, operating_company: issuer,
                                         name: 'SYNTHETIC activity denied unit', code: 'ACTIVITY_DENIED', active: true)
    state = { ready: Queue.new, results: Queue.new }
    worker = nil
    account.with_lock('FOR NO KEY UPDATE') do
      worker = native_activity_worker(state)
      wait_for_native_activity_lock(state)
      JrcCrm::UserBusinessUnit.where(account: account, user: operator.user).sole.update!(
        scope: 'BUSINESS_UNIT', company_id: issuer.id, business_unit_id: other.id
      )
    end
    result = joined_native_activity_result(worker, state)
    expect(result.class.name).to eq('ActiveRecord::RecordNotFound')
    expect(account.jrc_crm_activities.where(contact: contact).count).to eq(1)
    expect(account.jrc_crm_leads.where(contact: contact).count).to eq(1)
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'activity_created').count).to eq(1)
  end

  it 'revalidates the role after a real worker wait even when its existing Lead and CRM flag remain' do
    role = create(:custom_role, account: account, name: 'SYNTHETIC concurrent activity role',
                                permissions: %w[contact_manage jrc_crm jrc_contact_center_view jrc_contact_center_operate])
    operator.update!(custom_role: role)
    state = { ready: Queue.new, results: Queue.new }
    worker = nil
    account.with_lock('FOR NO KEY UPDATE') do
      worker = native_activity_worker(state)
      wait_for_native_activity_lock(state)
      role.update!(permissions: role.permissions - ['jrc_crm'])
    end
    result = joined_native_activity_result(worker, state)
    expect(result.class.name).to eq('Pundit::NotAuthorizedError')
    expect(operator.reload.crm_enabled?).to be true
    expect(account.jrc_crm_activities.where(contact: contact).count).to eq(1)
    expect(account.jrc_crm_leads.where(contact: contact).count).to eq(1)
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'activity_created').count).to eq(1)
  end
end

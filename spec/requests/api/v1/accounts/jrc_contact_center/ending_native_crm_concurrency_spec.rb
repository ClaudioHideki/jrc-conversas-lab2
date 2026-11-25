require 'rails_helper'
require 'timeout'

# Real native Lead/Audit writes and PostgreSQL contention. No mock of native
# authorization, CRM persistence, member refresh or the account authority mutex.
RSpec.describe 'Native CRM ending destination under concurrent original authority changes' do
  self.use_transactional_tests = false

  include_context 'with native ending execution original evidence'
  include_context 'with native ending attempt operators'

  let(:operator) { attempt_operator }
  let(:contact) { create(:contact, account: account, company_id: issuer.id, name: 'SYNTHETIC concurrent CRM contact') }
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
    raise 'Owned native CRM concurrency database required' unless owned
    raise 'Committed CRM concurrency fixtures required' if ApplicationRecord.connection.transaction_open?

    example.run
  end

  before do
    account.enable_features!('jrc_crm', 'jrc_customer_master')
    operator.update!(crm_enabled: true)
    reference
  end

  def native_crm_worker(state)
    ids = [account.id, reference.id]
    Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        state[:ready] << connection.raw_connection.backend_pid
        owner = Account.find(ids.first)
        context = JrcContactCenter::EndingActions::OriginalActorContext.new(account: owner, origin_id: ids.last)
        result = context.call do |member, origin|
          JrcContactCenter::EndingActions::CrmLeadDestination.new(account: Account.find(ids.first), member: member).call(origin: origin)
        end
        state[:results] << result
      end
    rescue StandardError => e
      state[:results] << e
    end
  end

  def wait_for_native_crm_lock(state)
    pid = Timeout.timeout(8) { state[:ready].pop }
    sql = "SELECT count(*) FROM pg_stat_activity WHERE pid=#{Integer(pid)} AND wait_event_type='Lock'"
    Timeout.timeout(8) do
      ApplicationRecord.connection.uncached { sleep 0.02 until ApplicationRecord.connection.select_value(sql).to_i == 1 }
    end
    pid
  end

  def join_native_crm_workers(workers)
    workers.each do |worker|
      worker.join(20)
      raise 'Synthetic native CRM worker remained active' if worker.alive?
    end
  end

  it 'serializes duplicate native operations into one Lead and creation audit with two distinct PostgreSQL workers' do
    state = { ready: Queue.new, results: Queue.new }
    workers = []
    pids = []
    account.with_lock('FOR NO KEY UPDATE') do
      2.times do
        workers << native_crm_worker(state)
        pids << wait_for_native_crm_lock(state)
      end
    end
    join_native_crm_workers(workers)
    results = 2.times.map { Timeout.timeout(8) { state[:results].pop } }
    expect(results).to all(be_a(Hash))
    expect(results.map { |result| result.fetch(:lead).id }.uniq.length).to eq(1)
    expect(results.map { |result| result.fetch(:created) }.sort_by(&:to_s)).to eq([false, true])
    expect(pids.uniq.length).to eq(2)
    expect(pids).not_to include(ApplicationRecord.connection.raw_connection.backend_pid)
    expect(account.jrc_crm_leads.where(contact: contact).count).to eq(1)
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'lead_created').count).to eq(1)
  end

  it 'revalidates CRM eligibility after an actual blocked worker resumes from account authority revocation' do
    state = { ready: Queue.new, results: Queue.new }
    workers = []
    account.with_lock('FOR NO KEY UPDATE') do
      workers << native_crm_worker(state)
      wait_for_native_crm_lock(state)
      operator.update!(crm_enabled: false)
    end
    join_native_crm_workers(workers)
    result = Timeout.timeout(8) { state[:results].pop }
    expect(result.class.name).to eq('Pundit::NotAuthorizedError')
    expect(account.jrc_crm_leads.where(contact: contact)).to be_empty
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'lead_created')).to be_empty
    expect(JrcContactCenter::EndingActionExecution.where(account: account)).to be_empty
  end

  it 'revalidates unit coverage after actual contention without borrowing the configuration administrator scope' do
    other = JrcCrm::BusinessUnit.create!(account: account, operating_company: issuer,
                                         name: 'SYNTHETIC denied CRM unit', code: 'CRM_DENIED', active: true)
    state = { ready: Queue.new, results: Queue.new }
    workers = []
    account.with_lock('FOR NO KEY UPDATE') do
      workers << native_crm_worker(state)
      wait_for_native_crm_lock(state)
      binding = JrcCrm::UserBusinessUnit.where(account: account, user: operator.user).sole
      binding.update!(scope: 'BUSINESS_UNIT', company_id: issuer.id, business_unit_id: other.id)
    end
    join_native_crm_workers(workers)
    result = Timeout.timeout(8) { state[:results].pop }
    expect(result.class.name).to eq('ActiveRecord::RecordNotFound')
    expect(account.jrc_crm_leads.where(contact: contact)).to be_empty
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'lead_created')).to be_empty
    expect(JrcContactCenter::EndingActionExecution.where(account: account)).to be_empty
  end

  it 'rechecks the native CRM profile permission after an actual PostgreSQL Contact wait' do
    role = create(:custom_role, account: account, name: 'SYNTHETIC concurrent native CRM authority',
                                permissions: %w[contact_manage jrc_crm jrc_contact_center_view jrc_contact_center_operate])
    operator.update!(custom_role: role)
    expect(JrcOperations::Access.crm?(operator.reload)).to be true
    state = { ready: Queue.new, results: Queue.new }
    workers = []
    contact.with_lock do
      workers << native_crm_worker(state)
      wait_for_native_crm_lock(state)
      role.update!(permissions: role.permissions - ['jrc_crm'])
    end
    join_native_crm_workers(workers)
    result = Timeout.timeout(8) { state[:results].pop }
    expect(result.class.name).to eq('Pundit::NotAuthorizedError')
    expect(operator.reload.crm_enabled?).to be true
    expect(account.jrc_crm_leads.where(contact: contact)).to be_empty
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'lead_created')).to be_empty
    expect(JrcContactCenter::EndingActionExecution.where(account: account)).to be_empty
  end

  it 'revalidates the immutable company link after waiting for the native Contact edit lock' do
    other = account.master_companies.create!(name: 'SYNTHETIC concurrent contact company edit')
    state = { ready: Queue.new, results: Queue.new }
    workers = []
    contact.with_lock do
      workers << native_crm_worker(state)
      wait_for_native_crm_lock(state)
      contact.update!(company_id: other.id)
    end
    join_native_crm_workers(workers)
    result = Timeout.timeout(8) { state[:results].pop }
    expect(result.class.name).to eq('JrcContactCenter::OperationError')
    expect(result.code).to eq('ending_customer_reference_changed')
    expect(account.jrc_crm_leads.where(contact: contact)).to be_empty
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'lead_created')).to be_empty
    expect(reference.reload.private_origin_evidence['company_id']).to eq(issuer.id)
  end

  it 'rechecks the existing native Lead unit after an actual PostgreSQL Contact wait' do
    business.update!(company: issuer)
    JrcCrm::UserBusinessUnit.where(account: account, user: operator.user).sole.update!(
      scope: 'BUSINESS_UNIT', company_id: issuer.id, business_unit_id: business.id
    )
    other = JrcCrm::BusinessUnit.create!(account: account, company: issuer, operating_company: issuer,
                                         name: 'SYNTHETIC moved CRM unit', code: 'CRM_MOVED', active: true)
    lead = account.jrc_crm_leads.create!(owner: operator.user, contact: contact, business_unit_id: business.id,
                                        name: 'SYNTHETIC moved owned native Lead')
    visible = JrcCrm::OrganizationalVisibility.new(account: account, user: operator.user, relation: account.jrc_crm_leads).call
    expect(visible.where(id: lead.id)).to exist
    context = JrcContactCenter::EndingActions::OriginalActorContext.new(account: account, origin_id: reference.id)
    allowed = context.call do |current_member, current_origin|
      JrcContactCenter::EndingActions::CrmLeadDestination.new(account: account, member: current_member).call(origin: current_origin)
    end
    expect(allowed).to eq(lead: lead, created: false)
    state = { ready: Queue.new, results: Queue.new }
    workers = []
    contact.with_lock do
      workers << native_crm_worker(state)
      wait_for_native_crm_lock(state)
      lead.update!(business_unit_id: other.id)
    end
    join_native_crm_workers(workers)
    result = Timeout.timeout(8) { state[:results].pop }
    expect(result.class.name).to eq('ActiveRecord::RecordNotFound')
    expect(account.jrc_crm_leads.where(contact: contact).sole.business_unit_id).to eq(other.id)
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'lead_created')).to be_empty
    expect(JrcContactCenter::EndingActionExecution.where(account: account)).to be_empty
  end
end

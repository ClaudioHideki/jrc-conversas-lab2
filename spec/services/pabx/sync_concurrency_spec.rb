require 'rails_helper'
require 'timeout'

RSpec.describe 'PABX PostgreSQL concurrent jobs', :pabx, type: :service do
  self.use_transactional_tests = false

  before do
    raise 'Expected test database' unless Rails.env.test? && ActiveRecord::Base.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Fixture must be committed' if ActiveRecord::Base.connection.transaction_open?
    Pabx::SyncJob; Pabx::Sync; Pabx::Provider; Pabx::Contract; TelephonyCallRecord
    @integration = create(:telephony_integration, account: create(:account, name: 'PABX disposable concurrency'),
                          pabx_settings: pabx_settings, pabx_username: 'synthetic-user', pabx_password: 'synthetic-password')
    @own_accounts = [@integration.account]
    @threads = []
    @release = Queue.new
    @entered = Queue.new
    @outcomes = Queue.new
    allow(Resolv).to receive(:getaddresses).with('pbx.example.test').and_return(['93.184.216.34'])
    stub_request(:post, 'https://pbx.example.test/api/v1/auth/login').to_return(body: { token: 'synthetic-token' }.to_json)
    stub_request(:get, 'https://pbx.example.test/api/v1/admin/dashboard-extension').to_return(body: { accountcode: '8' }.to_json)
    counter = 0
    mutex = Mutex.new
    stub_request(:post, 'https://pbx.example.test/api/v1/admin/relatorio-cdr/search').to_return do
      index = mutex.synchronize { counter += 1 }
      if index == 1
        @entered << true
        Timeout.timeout(10) { @release.pop }
      end
      { body: { total: 1, calls: [pabx_row] }.to_json }
    end
  end

  after do
    @release << true if @release
    @threads&.each { |thread| thread.join(20) }
    raise 'A test worker is still active' if @threads&.any?(&:alive?)
    @own_accounts&.each do |account|
      TelephonyCallRecord.where(account_id: account.id).delete_all
      account.destroy!
    end
  end

  it 'serializes concurrent jobs of the same integration using a real PostgreSQL row lock' do
    account_id = @integration.account_id
    integration_id = @integration.id
    @threads << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection { @outcomes << Pabx::SyncJob.perform_now(account_id, integration_id) }
    rescue StandardError => error
      @outcomes << error
    end
    Timeout.timeout(5) { @entered.pop }
    pid = Queue.new
    @threads << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        pid << connection.select_value('SELECT pg_backend_pid()')
        @outcomes << Pabx::SyncJob.perform_now(account_id, integration_id)
      end
    rescue StandardError => error
      @outcomes << error
    end
    backend = Timeout.timeout(5) { pid.pop }.to_i
    blocked = false
    Timeout.timeout(5) do
      until blocked
        blocked = ActiveRecord::Base.connection.select_value("SELECT wait_event_type = 'Lock' FROM pg_stat_activity WHERE pid = #{backend}")
        sleep 0.02 unless blocked
      end
    end
    expect(blocked).to be(true)
    @release << true
    Timeout.timeout(10) { @threads.each(&:join) }
    expect(2.times.map { @outcomes.pop }).to eq([1, 1])
    expect(TelephonyCallRecord.where(account_id: account_id).count).to eq(1)
    expect(@integration.reload.pabx_sync_state['cursor']).to be_present
  end

  it 'allows another Account integration to progress while the first Account row is locked' do
    other = create(:telephony_integration, account: create(:account, name: 'PABX disposable second scope'),
                   pabx_settings: pabx_settings, pabx_username: 'synthetic-user', pabx_password: 'synthetic-password')
    @own_accounts << other.account
    @threads << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection { @outcomes << Pabx::SyncJob.perform_now(@integration.account_id, @integration.id) }
    rescue StandardError => error
      @outcomes << error
    end
    Timeout.timeout(5) { @entered.pop }
    second = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection { @outcomes << Pabx::SyncJob.perform_now(other.account_id, other.id) }
    rescue StandardError => error
      @outcomes << error
    end
    @threads << second
    expect(second.join(5)).not_to be_nil
    @release << true
    Timeout.timeout(10) { @threads.each(&:join) }
    expect(2.times.map { @outcomes.pop }).to eq([1, 1])
    expect(TelephonyCallRecord.where(account_id: @integration.account_id).count).to eq(1)
    expect(TelephonyCallRecord.where(account_id: other.account_id).count).to eq(1)
  end
end

require 'rails_helper'

RSpec.describe 'NICO transport connection occupancy' do
  self.use_transactional_tests = false

  it 'returns an idle database connection before waiting on the provider' do
    pool = ActiveRecord::Base.connection_pool
    pool.connection.execute('SELECT 1')
    payload = { request_id: SecureRandom.uuid, account_id: 1, kind: 'operator', message: 'Hello', context: {}, history: [] }
    with_modified_env NICO_MODE: 'fixture', NICO_RUNTIME_URL: 'http://runtime:3108',
                      NICO_SERVICE_TOKEN: 'local-test-token-only-not-for-production' do
      stub_request(:post, 'http://runtime:3108/v1/operate').to_return do
        expect(pool.active_connection?).to be_falsey
        { status: 200, body: { request_id: payload[:request_id], account_id: 1, reply: 'Hello',
                              tool: '', arguments: '{}', mode: 'fixture', model: 'fixture', usage: nil }.to_json }
      end
      expect(JrcNico::RuntimeClient.new.operate(payload)['reply']).to eq('Hello')
    end
  ensure
    pool&.release_connection
  end

  it 'preserves an existing transaction instead of returning its connection to the pool' do
    pool = ActiveRecord::Base.connection_pool
    payload = { request_id: SecureRandom.uuid, account_id: 1, kind: 'operator', message: 'Hello', context: {}, history: [] }
    with_modified_env NICO_MODE: 'fixture', NICO_RUNTIME_URL: 'http://runtime:3108',
                      NICO_SERVICE_TOKEN: 'local-test-token-only-not-for-production' do
      ActiveRecord::Base.transaction do
        connection = pool.active_connection?
        stub_request(:post, 'http://runtime:3108/v1/operate').to_return do
          expect(pool.active_connection?).to equal(connection)
          expect(connection.transaction_open?).to be(true)
          { status: 200, body: { request_id: payload[:request_id], account_id: 1, reply: 'Hello',
                                tool: '', arguments: '{}', mode: 'fixture', model: 'fixture', usage: nil }.to_json }
        end
        expect(JrcNico::RuntimeClient.new.operate(payload)['reply']).to eq('Hello')
      end
    end
  ensure
    pool&.release_connection
  end
end

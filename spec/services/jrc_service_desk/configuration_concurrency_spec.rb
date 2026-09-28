# frozen_string_literal: true
require 'rails_helper'
require 'timeout'

RSpec.describe 'CP6 catalogue duplicate submission', :sd_concurrency, type: :service do
  self.use_transactional_tests = false
  include_context 'JRC Service Desk domain'
  around do |example|
    if ENV['JRC_SD_CONCURRENCY'] == '1' && Rails.env.test?
      example.run
    else
      skip 'PENDENTE - isolated disposable PostgreSQL with committed fixtures is required'
    end
  end

  it 'serializes identical administrative creation into one record and native audit receipt' do
    sd_as_admin!
    actor = sd_context; unit_id = sd_unit.id
    raise 'Dedicated fixture transaction must be committed' if ActiveRecord::Base.connection.transaction_open?
    key = SecureRandom.uuid; gate = Queue.new; outcomes = Queue.new
    attributes = { name: 'Concurrent test', code: SecureRandom.hex(8), active: true }
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          begin
            result = JrcServiceDesk::ConfigurationService.new(user_context: actor).create(resource: 'categories', unit_id: unit_id,
              attributes: attributes, idempotency_key: key)
            outcomes << [result.record.id, result.audit_id]
          rescue StandardError => error
            outcomes << error
          end
        end
      end
    end
    2.times { gate << true }
    Timeout.timeout(30) { threads.each(&:join) }
    values = 2.times.map { outcomes.pop }
    expect(values.all? { |row| row.is_a?(Array) }).to be(true)
    expect(values.uniq.length).to eq(1)
    expect(JrcServiceDesk::Category.where(account_id: sd_account.id, unit_id: unit_id, code: attributes[:code]).count).to eq(1)
    expect(Audited::Audit.where(id: values.first.last).count).to eq(1)
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
    threads&.each(&:join)
  end
end

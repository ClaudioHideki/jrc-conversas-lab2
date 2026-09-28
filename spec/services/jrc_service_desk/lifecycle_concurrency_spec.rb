# frozen_string_literal: true
require 'rails_helper'
require 'timeout'

RSpec.describe 'Lifecycle duplicate submission and locking', :sd_concurrency, type: :service do
  self.use_transactional_tests = false
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  around do |example|
    if ENV['JRC_SD_CONCURRENCY'] == '1' && Rails.env.test?
      example.run
    else
      skip 'PENDENTE - dedicated disposable Docker/local PostgreSQL required'
    end
  end

  it 'concurrently pauses once for identical keys, preserving one pause and transition' do
    policy = lc_publish; row = sd_ticket
    actor = sd_context; ticket_id = row.id
    attrs = { rule_key: 'pause', reason_code: 'customer', expected_lock_version: row.lock_version, expected_policy_version_id: policy.current_version_id }
    raise 'Fixture transaction must be committed' if ActiveRecord::Base.connection.transaction_open?
    gate = Queue.new; outcomes = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          begin
            result = JrcServiceDesk::LifecycleTransitionService.new(user_context: actor).call(ticket_id: ticket_id, attributes: attrs, idempotency_key: 'concurrent-pause')
            outcomes << result.id
          rescue StandardError => e
            outcomes << e
          end
        end
      end
    end
    2.times { gate << true }
    Timeout.timeout(30) { threads.each(&:join) }
    ids = 2.times.map { outcomes.pop }
    expect(ids.all? { |id| id.is_a?(Integer) }).to be(true)
    expect(ids.uniq.length).to eq(1)
    expect(row.lifecycle_pauses.count).to eq(1)
    expect(row.lifecycle_transitions.count).to eq(1)
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
    threads&.each(&:join)
  end
end

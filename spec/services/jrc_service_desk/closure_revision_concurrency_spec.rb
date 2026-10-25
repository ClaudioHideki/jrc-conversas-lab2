# frozen_string_literal: true

require 'rails_helper'
require 'timeout'
RSpec.describe 'Closure revision HTTP concurrency', :sd_concurrency, type: :request do
  self.use_transactional_tests = false
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  around do |example|
    if ENV['JRC_SD_INTEGRATED_CONCURRENCY'] == '1' && Rails.env.test? && %w[jrc_sd_integrated_concurrency_20261023_test
                                                                            jrc_sd_five_concurrency_20261024_test].include?(ActiveRecord::Base.connection.current_database)
      example.run
    else
      skip 'Requires the isolated committed synthetic concurrency database'
    end
  end

  it 'uses independent connections and commits only one application when two reviewed batches race for the same ticket' do
    sd_as_admin!
    old = lc_definition(tracked: true)
    old['transitions'].each { |r| r['requirements']['solution'] = true if %w[resolve close].include?(r['action']) }
    source = lc_publish(definition: old).current_version
    target = lc_publish(definition: JrcServiceDesk::ClosureRevisionBinding.proposal(source), expected_version: 1).current_version
    ticket = sd_ticket(lifecycle_policy_version: source)
    approved = JrcServiceDesk::ClosureRevisionService.new(user_context: sd_context).preview(unit_id: sd_unit.id,
                                                                                            source_version_id: source.id, target_version_id: target.id, ticket_ids: [ticket.id], operational_review: true, review_reason: 'Synthetic concurrent administrative review')
    headers = sd_user.create_new_auth_token
    expect(ActiveRecord::Base.connection.transaction_open?).to be(false)
    gate = Queue.new
    results = Queue.new
    workers = 2.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          pid = connection.select_value('SELECT pg_backend_pid()')
          gate.pop
          client = ActionDispatch::Integration::Session.new(Rails.application)
          client.post("/api/v1/accounts/#{sd_account.id}/jrc_service_desk/closure_revisions", as: :json,
                                                                                              headers: headers.merge('Idempotency-Key' => "concurrent-revision-#{index}"), params: { unit_id: sd_unit.id, receipt: approved[:receipt] })
          results << { http: client.response.status, status: client.response.parsed_body.dig('result', 'results', 0, 'status'), pid: pid }
        rescue StandardError => e
          results << e
        end
      end
    end
    2.times { gate << true }
    Timeout.timeout(30) { workers.each(&:join) }
    outcomes = 2.times.map { results.pop }
    expect(outcomes).to all(be_a(Hash))
    expect(outcomes.map { |r| r[:pid] }.uniq.size).to eq(2)
    expect(outcomes.map { |r| r[:http] }).to eq([201, 201])
    expect(outcomes.map { |r| r[:status] }.sort).to eq(%w[applied conflict])
    expect(ticket.reload.lifecycle_policy_version_id).to eq(source.id)
    expect(ticket.ticket_events.where(event_type: 'closure_policy_revised').count).to eq(1)
    expect(ticket.lock_version).to eq(1)
    puts 'CLOSURE_CONCURRENCY_PROOF ' + outcomes.to_json
  ensure
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end
end

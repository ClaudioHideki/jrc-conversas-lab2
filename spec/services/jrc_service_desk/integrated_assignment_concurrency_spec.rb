# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

RSpec.describe 'Integrated HTTP assignment with independent PostgreSQL transactions', :sd_concurrency, type: :request do
  self.use_transactional_tests = false
  include_context 'JRC Service Desk domain'

  around do |example|
    if ENV['JRC_SD_INTEGRATED_CONCURRENCY'] == '1' && Rails.env.test? &&
       %w[jrc_sd_integrated_concurrency_20261023_test jrc_sd_bc_portal_concurrency_20261025_test].include?(
         ActiveRecord::Base.connection.current_database
       ) && ActiveRecord::Base.connection_db_config.adapter == 'postgresql'
      example.run
    else
      skip 'Requires the explicitly isolated, committed synthetic concurrency database'
    end
  end

  it 'accepts one of two simultaneous assignments and returns a conflict to the stale writer' do
    sd_as_admin!
    team = create(:team, account: sd_account)
    agents = Array.new(2) { create(:account_user, account: sd_account, role: :agent) }
    members = agents.map do |agent|
      create(:team_member, team: team, user: agent.user)
      create(:jrc_sd_membership, unit: sd_unit, account_user: agent)
    end
    ticket = sd_ticket(team: team)
    commands = agents.map do |agent|
      { headers: agent.user.create_new_auth_token,
        params: { assignment: { assignee_account_user_id: agent.id }, expected_lock_version: ticket.lock_version } }
    end
    path = "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/tickets/#{ticket.id}/assign"
    expect(ActiveRecord::Base.connection.transaction_open?).to be(false)
    gate = Queue.new
    results = Queue.new
    workers = commands.map do |command|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          pid = connection.select_value('SELECT pg_backend_pid()')
          gate.pop
          client = ActionDispatch::Integration::Session.new(Rails.application)
          client.post(path, **command, as: :json)
          results << { status: client.response.status, backend_pid: pid }
        rescue StandardError => error
          results << error
        end
      end
    end
    2.times { gate << true }
    Timeout.timeout(30) { workers.each(&:join) }
    outcomes = Array.new(2) { results.pop }
    expect(outcomes).to all(be_a(Hash))
    expect(outcomes.map { |row| row[:backend_pid] }.uniq.size).to eq(2)
    expect(outcomes.map { |row| row[:status] }.sort).to eq([200, 409])
    expect(members.map(&:id)).to include(ticket.reload.assignee_membership_id)
    expect(ticket.ticket_events.where(event_type: 'ticket_assigned').count).to eq(1)
    expect(ticket.lock_version).to eq(1)
    puts 'CONCURRENCY_PROOF ' + outcomes.to_json
  ensure
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end
end

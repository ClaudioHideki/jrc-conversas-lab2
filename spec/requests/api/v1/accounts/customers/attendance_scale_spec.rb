require 'rails_helper'

RSpec.describe 'Synthetic native attendance source scale', type: :request do
  # Shared read-only instrumentation omits SQL text, binds and record content.
  def capture_attendance_queries(rows, &)
    subscriber = lambda do |_name, first, last, _id, payload|
      next if payload[:name] == 'SCHEMA'

      error = payload[:exception_object]
      rows << { milliseconds: ((last - first) * 1_000).round(2), cached: payload[:cached] == true,
                tables: payload[:sql].scan(/(?:FROM|INTO|UPDATE|JOIN)\s+"?([a-z_]+)"?/i).flatten.uniq,
                error: error&.class&.name, cause: error&.cause&.class&.name }
    end
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record', monotonic: true, &)
  end

  context 'with one thousand real conversations and public/private messages' do
    # Keep this owned synthetic cohort for review; do not benchmark thousands of
    # uncommitted inserts against PostgreSQL's pre-fixture four-row estimates.
    self.use_transactional_tests = false
    around { |example| travel_to(Time.utc(2026, 11, 6, 19)) { example.run } }

    let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
    let(:actor) { create(:user, account: account, role: :administrator) }
    let(:company) { account.master_companies.create!(name: 'Synthetic attendance scale company') }
    let(:contact) { create(:contact, account: account, company_id: company.id) }
    let(:widget) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
    let(:api) { create(:channel_api, account: account).inbox }
    let(:links) { [widget, api].map { |inbox| create(:contact_inbox, contact: contact, inbox: inbox) } }

    before do
      unless ActiveRecord::Base.connection.current_database == 'jrc_rel_v2_candidate_test'
        raise 'Only the owned synthetic candidate database is allowed'
      end

      account.enable_features!('jrc_customer_master')
    end

    it 'keeps company totals, channel filtering and hidden inbox permissions exact without projecting message contents' do
      setup_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      1_000.times do |index|
        inbox = index.even? ? widget : api
        conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: links[index % 2],
                                             created_at: Time.utc(2026, 11, 6, 18))
        create(:message, account: account, conversation: conversation, sender: contact, private: false, created_at: Time.current)
        if (index % 10).zero?
          create(:message, account: account, conversation: conversation, sender: actor, message_type: :outgoing, private: true,
                           content: 'SYNTHETIC_PRIVATE_SCALE_CANARY', created_at: Time.current)
        end
        if (index % 20).zero?
          create(:message, account: account, conversation: conversation, sender: actor, message_type: :outgoing, private: false,
                           created_at: Time.current)
        end
        conversation.update!(status: :resolved) if (index % 4).zero?
      end
      setup_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - setup_started
      connection = ActiveRecord::Base.connection
      %w[messages conversations contacts].each { |table| connection.execute("ANALYZE #{connection.quote_table_name(table)}") }
      table_estimates = connection.select_rows('SELECT relname, reltuples::bigint FROM pg_class ' \
                                               "WHERE relname IN ('messages', 'conversations', 'contacts')")
      path = "/api/v1/accounts/#{account.id}/customers/companies/#{company.id}/attendance"
      headers = actor.create_new_auth_token
      period = { from: '2026-11-06', to: '2026-11-06' }
      observations = []
      [nil, 'Channel::Api', nil].each do |channel|
        query_times = []
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        capture_attendance_queries(query_times) do
          get path, headers: headers, params: period.merge(channel: channel)
        end
        observations << { channel: channel || 'all', seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(4),
                          uncached_queries: query_times.count { |row| !row[:cached] }, response_bytes: response.body.bytesize,
                          slowest_queries: query_times.sort_by { |row| -row[:milliseconds] }.first(3),
                          service_desk_available: response.parsed_body.dig('ticket_sla', 'available') }
        expect(response).to have_http_status(:ok), "Attendance response #{response.status}"
        expect(response.parsed_body).to include('messages' => { 'incoming' => channel ? 500 : 1_000, 'outgoing' => channel ? 0 : 50 })
        expect(response.parsed_body.fetch('conversations')).to include('created' => channel ? 500 : 1_000)
        expect(response.body).not_to include('SYNTHETIC_PRIVATE_SCALE_CANARY', 'email', 'phone_number')
      end
      agent = create(:user, account: account, role: :agent)
      get path, headers: agent.create_new_auth_token, params: period
      expect(response.parsed_body.fetch('conversations').fetch('created')).to eq(0)
      puts({ dataset: 'synthetic_company_attendance', account_id: account.id, company_id: company.id, contact_id: contact.id,
             committed_cohort_preserved: true, statistics_updated_only_in_guarded_candidate_db: true, table_estimates: table_estimates,
             conversations: 1_000, fixture_messages: 1_150, private_messages: 100,
             all_messages_by_type: account.messages.reorder(nil).group(:message_type).count,
             setup_seconds: setup_seconds.round(3), observations: observations }.to_json)
    end
  end

  context 'with calendar-bound native Service Desk clocks' do
    include_context 'JRC Service Desk domain'
    include JrcServiceDeskLifecycleFixtures
    around { |example| travel_to(Time.utc(2026, 11, 6, 18)) { example.run } }

    it 'does not turn a weekend clock candidate into an SLA breach and keeps policy lookups bounded across one hundred tickets' do
      expect(ActiveRecord::Base.connection.select_value('SELECT current_database()')).to eq('jrc_rel_v2_candidate_test')
      sql_trace = []
      sd_as_admin!
      sd_account.update!(reporting_timezone: 'America/Sao_Paulo')
      sd_account.enable_features!('jrc_customer_master')
      lc_publish(definition: lc_definition(tracked: true))
      setup_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      100.times do
        ticket = sd_ticket(opened_at: Time.current)
        lc_snapshot(ticket)
        lc_execute(ticket, 'work_status')
      end
      setup_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - setup_started
      clocks = JrcServiceDesk::SlaClock.where(account: sd_account).order(:id)
      original = clocks.pluck(:id, :state, :elapsed_seconds, :due_at, :updated_at)
      travel_to(Time.utc(2026, 11, 8, 18))
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      capture_attendance_queries(sql_trace) do
        get "/api/v1/accounts/#{sd_account.id}/customers/contacts/#{sd_contact.id}/attendance", headers: sd_user.create_new_auth_token,
                                                                                                params: { from: '2026-11-06', to: '2026-11-08' }
      end
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      policy_queries = sql_trace.count { |row| row[:tables].include?('jrc_service_desk_lifecycle_policy_versions') }
      expect(response).to have_http_status(:ok), "Attendance response #{response.status}"
      expect(response.parsed_body.fetch('ticket_sla')).to include('available' => true, 'clocks' => 200,
                                                                  'currently_breached_running_clocks' => 0)
      expect(clocks.reload.pluck(:id, :state, :elapsed_seconds, :due_at, :updated_at)).to eq(original)
      puts({ dataset: 'synthetic_attendance_calendar_clocks', tickets: 100, clocks: 200, policy_queries: policy_queries,
             setup_seconds: setup_seconds.round(3), request_seconds: elapsed.round(4) }.to_json)
      expect(policy_queries).to be <= 1
    ensure
      if sql_trace
        puts({ calendar_sql_errors: sql_trace.select { |row| row[:error] }.first(5),
               slowest_calendar_queries: sql_trace.sort_by { |row| -row[:milliseconds] }.first(5) }.to_json)
      end
    end
  end
end

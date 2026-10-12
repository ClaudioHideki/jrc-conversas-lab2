require 'rails_helper'

RSpec.describe 'E4 basic scoped pagination measurements', :approval_core, type: :request do
  it 'measures policies, requests and audit using only a disposable synthetic dataset' do
    scope = approval_scope
    author = approval_actor(scope)
    approver = approval_actor(scope, permissions: ['jrc_approvals_decide'])
    definition = approval_definition([approver])
    published = approval_publish(scope, author, definition)
    200.times do |index|
      JrcApprovals::Policy.create!(
        account: scope[:account], author: author, code: "benchmark_#{index}", name: "Synthetic benchmark #{index}",
        module_key: 'synthetic', event_key: 'review', issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id,
        draft_definition: definition
      )
    end
    records = Array.new(120) { |index| approval_request(scope, author, key: "benchmark_#{index}") }
    record = records.first
    240.times do |index|
      JrcApprovals::Ledger.audit!(account: scope[:account], actor: author, event: 'synthetic_benchmark', key: "benchmark:audit:#{index}",
                                  data: { reason: 'Disposable measurement' }, request_id: record.id, policy_version_id: published.current_version_id)
    end
    url = "/api/v1/accounts/#{scope[:account].id}/approvals"
    headers = author.user.create_new_auth_token
    output = []
    { 'policies' => 201, 'requests' => 120, "requests/#{record.id}/audit" => 241 }.each do |path, count|
      tables = Hash.new(0)
      queries = 0
      listener = lambda do |*, payload|
        next if payload[:cached] || payload[:name] == 'SCHEMA'

        queries += 1
        table = payload[:sql][/\bFROM\s+"?([a-z_]+)/i, 1]
        tables[table] += 1 if table
      end
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ActiveSupport::Notifications.subscribed(listener, 'sql.active_record') do
        get "#{url}/#{path}", params: { page: 2, per_page: 25 }, headers: headers
      end
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      expect(response).to have_http_status(:ok)
      expect(response.headers['X-Total-Count'].to_i).to eq(count)
      expect(response.parsed_body.size).to eq(25)
      output << { endpoint: path.gsub(record.id.to_s, ':synthetic_id'), records: count, seconds: elapsed.round(6),
                  queries: queries, tables: tables, returned: response.parsed_body.size, scope: 'authorized synthetic unit' }
    end
    if ENV['JRC_E1_TEST_DATABASE'].present?
      report = { measurements: output, note: 'Basic local measurement; no production benchmark or volume SLA inferred.' }
      File.write('/evidence/e4-performance.json', JSON.pretty_generate(report))
    end
  end
end

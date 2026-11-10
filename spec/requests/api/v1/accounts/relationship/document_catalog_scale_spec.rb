require 'rails_helper'

RSpec.describe 'Native synthetic document catalog scale', type: :request do
  # Preserve this owned fixture cohort and its one private blob for review.
  self.use_transactional_tests = false

  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: actor)) }
  let(:company) { account.master_companies.create!(name: 'Synthetic document catalog scale company') }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, company: company) }
  let(:service) { JrcRelationship::CustomerDocuments.new(context) }
  let(:upload) { fixture_file_upload('jrc_projects_task.txt', 'text/plain') }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/documents" }
  let(:headers) { actor.create_new_auth_token }

  let(:expected) { {} }
  let(:fixture_timings) { {} }
  let(:first) do
    service.upload!(assignment_id: assignment.id, attributes: {
                      'title' => 'Synthetic catalog document 0', 'category' => 'evidence', 'change_reason' => 'Synthetic baseline upload'
                    }, upload: upload)
  end

  before do
    unless ActiveRecord::Base.connection.current_database == 'jrc_rel_v2_candidate_test'
      raise 'Only the owned synthetic candidate database is allowed'
    end

    account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    blob = first.versions.first!.file.blob
    expected[first.id] = 1
    # Actual native validated models/attachments; reuse one private synthetic blob.
    # This measures catalog queries, not scanner throughput or 1000 upload requests.
    999.times do |index|
      document = JrcRelationship::CustomerDocument.create!(account: account, assignment: assignment, title: "Synthetic catalog document #{index + 1}",
                                                           category: 'evidence', responsible: actor)
      version = document.versions.create!(account: account, uploaded_by: actor, number: 1, change_reason: 'Synthetic catalog version')
      version.file.attach(blob)
      expected[document.id] = 1
    end
    2.times do
      service.upload!(assignment_id: assignment.id, document_id: first.id,
                      attributes: { 'change_reason' => 'Native immutable version fixture' }, upload: upload)
    end
    expected[first.id] = 3
    fixture_timings[:seconds] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end

  it 'bounds latest-version queries on real pages of a thousand versioned documents while preserving private access and version pagination' do
    observations = []
    [[1, 5], [1, 25], [20, 50], [40, 25]].each do |page, size|
      queries = []
      subscriber = lambda do |_name, begin_at, end_at, _id, payload|
        next if payload[:name] == 'SCHEMA'

        queries << { tables: payload[:sql].scan(/(?:FROM|JOIN)\s+"?([a-z_]+)"?/i).flatten.uniq,
                     milliseconds: ((end_at - begin_at) * 1000).round(2), cached: payload[:cached] == true }
      end
      begin_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ActiveRecord::Base.uncached do
        ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record', monotonic: true) do
          get url, headers: headers, params: { assignment_id: assignment.id, page: page, per_page: size }
        end
      end
      rows = response.parsed_body.fetch('payload')
      expect([response.status, response.parsed_body.fetch('meta'),
              rows.size]).to match([200, include('total' => 1000, 'page' => page, 'per_page' => size), size])
      rows.each do |row|
        version = row.fetch('versions').sole
        expect([version['number'], version['download_available'],
                version.keys & %w[url signed_id key]]).to eq([expected.fetch(row.fetch('id')), false, []])
      end
      version_queries = queries.count { |query| query[:tables].include?('jrc_relationship_document_versions') }
      blob_queries = queries.count { |query| query[:tables].include?('active_storage_blobs') }
      observations << { page: page, per_page: size, seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - begin_at).round(4),
                        query_count: queries.size, version_queries: version_queries, blob_queries: blob_queries }
    end
    get "#{url}/#{first.id}", headers: headers, params: { page: 2, per_page: 2 }
    expect(response.parsed_body.fetch('versions_meta')).to include('total' => 3, 'page' => 2)
    expect(response.parsed_body.fetch('versions').pluck('number')).to eq([1])
    restricted = create(:user, account: account, role: :agent)
    get url, headers: restricted.create_new_auth_token, params: { assignment_id: assignment.id }
    expect(response).to have_http_status(:forbidden)
    foreign = create(:account)
    get "/api/v1/accounts/#{foreign.id}/relationship/documents", headers: headers,
                                                                 params: { assignment_id: assignment.id, account_id: account.id }
    expect(response).to have_http_status(:forbidden)
    report = { account_id: account.id, assignment_id: assignment.id, documents: 1000, versions: 1002,
               fixture_seconds: fixture_timings.fetch(:seconds).round(3),
               observations: observations, source: 'native validated synthetic models, one reused private blob plus two native version uploads',
               no_external_scanner_or_upload_load_claim: true }
    filename = "/tmp/document-catalog-scale-#{account.id}.json"
    File.write(filename, JSON.pretty_generate(report), mode: File::WRONLY | File::CREAT | File::EXCL)
    puts({ document_catalog_scale: report, report_path: filename }.to_json)
    expect(observations.map { |row| row.values_at(:version_queries, :blob_queries) }).to all(match([be <= 2, be <= 1]))
  end
end

require 'rails_helper'

RSpec.describe 'Native CS responsibility links at representative task scale', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:analyst) { create(:user, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: analyst) }
  let(:contact) { create(:contact, account: account) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: contact) }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship/team/#{analyst.id}" }
  let(:projects) do
    %w[Linked Unrelated].map do |name|
      JrcProjects::Projects::Create.call(account: account, actor: analyst,
                                         attributes: { name: "Synthetic #{name} project", contact_id: contact.id },
                                         idempotency_key: SecureRandom.uuid)
    end
  end
  let(:templates) do
    projects.each_with_index.map do |project, index|
      JrcProjects::Tasks::Create.call(account_user: member, project: project,
                                      attributes: { title: "Synthetic #{index} task", assignee_id: analyst.id },
                                      correlation_id: SecureRandom.uuid)
    end
  end

  before do
    database = ActiveRecord::Base.connection.select_value('SELECT current_database()')
    raise 'Owned candidate database required' unless database == 'jrc_rel_v2_candidate_test'

    account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm', 'jrc_projects')
  end

  it 'counts and paginates one thousand linked tasks while preserving one thousand unrelated native tasks' do
    templates
    JrcRelationship::HandoffCase.create!(account: account, assignment: assignment,
                                         source_type: 'JrcProjects::Project', source_id: projects.first.id)
    headers = actor.create_new_auth_token
    phase = :small
    requests = Hash.new(0)
    tables = Hash.new { |result, key| result[key] = Hash.new(0) }
    counter = lambda do |_name, _started, _finished, _id, event|
      next if event[:name] == 'SCHEMA' || event[:cached]

      requests[phase] += 1
      table = event[:sql].match(/\bFROM\s+"?([a-z_]+)/i)&.[](1) || 'other'
      tables[phase][table] += 1
    end
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
      get "#{base}/withdrawal_readiness", headers: headers
      get "#{base}/native_responsibilities", headers: headers, params: { kind: 'project_tasks' }
      get "#{base}/native_responsibilities", headers: headers, params: { kind: 'project_tasks' }
    end
    small_total = response.parsed_body.fetch('meta').fetch('total')
    templates.each_with_index do |template, index|
      # Model-validated synthetic seeding; not two thousand UI creation flows.
      rows = Array.new(999) do |number|
        template.attributes.except('id').merge('title' => "Synthetic #{index} task #{number + 1}",
                                               'project' => template.project, 'assignee' => analyst, 'created_by' => analyst)
      end
      JrcProjects::Task.create!(rows)
    end
    headers = actor.reload.create_new_auth_token
    total_tasks = JrcProjects::Task.where(account: account).count
    phase = :large
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
      get "#{base}/withdrawal_readiness", headers: headers
      expect(response).to have_http_status(:ok)
      counts = response.parsed_body.fetch('counts')
      expect([small_total, counts.fetch('project_tasks'), counts.fetch('projects'), total_tasks])
        .to eq([1, 1000, 1, 2000])
      get "#{base}/native_responsibilities", headers: headers, params: { kind: 'project_tasks' }
      expect([response.status, response.parsed_body.fetch('meta').fetch('total'), response.parsed_body.fetch('payload').length])
        .to eq([200, 1000, 10])
      get "#{base}/native_responsibilities", headers: headers, params: { kind: 'project_tasks', page: 100 }
    end
    expected = JrcProjects::Task.where(account: account, project: projects.first).order(id: :desc).limit(10).pluck(:id).reverse
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq(expected)
    expect(response.body).not_to include('Synthetic 1 task', 'Synthetic Unrelated project', 'custom_fields', 'attachments')
    puts({ linked_tasks: 1000, unrelated_tasks: 1000, native_projects: 2, requests_per_phase: 3,
           sql_queries: requests, query_tables: tables,
           elapsed_seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3),
           response_bytes: response.body.bytesize }.to_json)
    # Permit bounded page/auth work, never one extra query per candidate task.
    expect([response.body.bytesize < 16_384, requests[:large] <= requests[:small] + 20]).to eq([true, true])
  end
end

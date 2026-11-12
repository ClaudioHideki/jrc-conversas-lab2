require 'rails_helper'

RSpec.describe 'CS withdrawal across distinct implementation orders', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:analyst) { create(:user, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: analyst) }
  let(:contact) { create(:contact, account: account) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: contact) }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship/team/#{analyst.id}" }

  before do
    unless ActiveRecord::Base.connection.select_value('SELECT current_database()') == 'jrc_rel_v2_candidate_test'
      raise 'Owned candidate database required'
    end

    account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm', 'jrc_projects')
  end

  it 'paginates one thousand linked tasks across twenty five actual order origins and excludes unrelated work' do
    projects = Array.new(25) do |index|
      order = account.jrc_crm_sales_orders.create!(owner: actor, contact: contact, status: 'approved')
      project = JrcProjects::Projects::Create.call(account: account, actor: analyst,
                                                   attributes: { name: "Synthetic order project #{index}", contact_id: contact.id },
                                                   idempotency_key: "crm-order-implementation-#{order.id}")
      # Both canonical native implementations must retain the same authorization.
      if index.even?
        account.jrc_crm_backoffice_requests.create!(sales_order: order, contact: contact, owner: actor, requested_by: actor,
                                                    request_kind: 'fulfillment', title: 'Synthetic implementation',
                                                    metadata: { implementation_project_id: project.id.to_s })
      end
      JrcRelationship::HandoffCase.create!(account: account, assignment: assignment, source_type: order.class.name, source_id: order.id)
      template = JrcProjects::Tasks::Create.call(account_user: member, project: project,
                                                 attributes: { title: 'Synthetic linked task', assignee_id: analyst.id },
                                                 correlation_id: SecureRandom.uuid)
      JrcProjects::Task.create!(Array.new(39) do |number|
        template.attributes.except('id').merge('title' => "Synthetic linked task #{index}-#{number}",
                                               'project' => project, 'assignee' => analyst, 'created_by' => analyst)
      end)
      project
    end
    unrelated = JrcProjects::Projects::Create.call(account: account, actor: analyst,
                                                   attributes: { name: 'Synthetic unrelated project', contact_id: contact.id },
                                                   idempotency_key: SecureRandom.uuid)
    unrelated_task = JrcProjects::Tasks::Create.call(account_user: member, project: unrelated,
                                                     attributes: { title: 'Synthetic unrelated task', assignee_id: analyst.id },
                                                     correlation_id: SecureRandom.uuid)
    original_cases = JrcRelationship::HandoffCase.where(account: account).order(:id).map(&:attributes)
    headers = actor.create_new_auth_token
    queries = 0
    counter = ->(*event) { queries += 1 unless event.last[:name] == 'SCHEMA' || event.last[:cached] }
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
      get "#{base}/withdrawal_readiness", headers: headers
      expect([response.status, response.parsed_body.fetch('counts').slice('projects', 'project_tasks')])
        .to eq([200, { 'projects' => 25, 'project_tasks' => 1000 }])
      get "#{base}/native_responsibilities", headers: headers, params: { kind: 'projects', page: 3 }
      expect([response.status, response.parsed_body.fetch('meta'), response.parsed_body.fetch('payload').pluck('id')])
        .to eq([200, { 'total' => 25, 'per_page' => 10, 'page' => 3 }, projects.last(5).map(&:id)])
      get "#{base}/native_responsibilities", headers: headers, params: { kind: 'project_tasks', page: 100 }
    end
    expected = JrcProjects::Task.where(project: projects).order(id: :desc).limit(10).pluck(:id).reverse
    expect([response.status, response.parsed_body.fetch('meta'), response.parsed_body.fetch('payload').pluck('id')])
      .to eq([200, { 'total' => 1000, 'per_page' => 10, 'page' => 100 }, expected])
    expect(response.body).not_to include('Synthetic unrelated', 'custom_fields', 'attachments')
    expect(JrcRelationship::HandoffCase.where(account: account).order(:id).map(&:attributes)).to eq(original_cases)
    expect([JrcProjects::Project.where(id: projects.map(&:id) + [unrelated.id]).distinct.pluck(:owner_id), unrelated_task.reload.assignee_id])
      .to eq([[analyst.id], analyst.id])
    puts({ native_order_origins: 25, linked_tasks: 1000, unrelated_projects: 1, requests: 3, sql_queries: queries,
           elapsed_seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3), response_bytes: response.body.bytesize }.to_json)
  end
end

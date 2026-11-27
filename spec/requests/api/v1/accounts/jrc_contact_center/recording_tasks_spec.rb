# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Explicit native task creation from an authorized recording', :pabx do
  include_context 'with native manual recording task destination'

  let(:path) { "/api/v1/accounts/#{account.id}/jrc_contact_center/recordings/#{record.id}/tasks" }
  let(:headers) { actor.create_new_auth_token }

  def post_task(values = input)
    post path, headers: headers, params: { recording_task: values }, as: :json
  end

  def counts
    [JrcProjects::Task.where(account: account).count, JrcContactCenter::RecordingTaskLink.where(account: account).count,
     JrcProjects::AuditEvent.where(account: account, action: 'projects.task.created').count]
  end

  it 'creates and reloads the real native task link without returning private Task contents in the receipt' do
    post_task
    expect(response).to have_http_status(:ok)
    row = JrcContactCenter::RecordingTaskLink.where(account: account).sole
    expect(response.parsed_body).to eq('contract_version' => 1, 'account_id' => account.id.to_s,
                                       'recording_id' => record.id.to_s, 'link_id' => row.id.to_s)
    expect(response.headers.fetch('Cache-Control')).to include('private', 'no-store')
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body).to include('recording_id' => record.id.to_s, 'call_session_id' => source_call.id.to_s,
                            'call_id' => source_call.external_session_id, 'project_module_available' => true,
                            'meta' => { 'page' => 1, 'per_page' => 20, 'total' => 1, 'pages' => 1 })
    expect(body.fetch('items').sole).to include('id' => row.id.to_s, 'request_id' => request_id,
                                               'account_user_id' => member.id.to_s)
    expect(body.fetch('items').sole.fetch('target')).to include('kind' => 'project_task', 'id' => row.task_id.to_s,
                                                              'project_id' => project.id.to_s)
    expect(response.body).not_to include(input.fetch('task').fetch('title'), 'recording_reference', 'synthetic-password')
    expect(counts).to eq([1, 1, 1])
  end

  it 'revalidates the actor and returns the exact same link for an explicit identical retry' do
    post_task
    first = response.parsed_body
    post_task(input.deep_dup)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(first)
    expect(counts).to eq([1, 1, 1])
  end

  it 'rejects an altered body with a previously committed request ID without a second effect' do
    post_task
    changed = input.deep_dup
    changed.fetch('task')['title'] = 'SYNTHETIC conflicting API title'
    post_task(changed)
    expect(response).to have_http_status(:conflict)
    expect(counts).to eq([1, 1, 1])
  end

  it 'does not accept unauthenticated creation or a foreign account route' do
    post path, params: { recording_task: input }, as: :json
    expect(response).to have_http_status(:unauthorized)
    foreign = create(:account)
    post path.sub("accounts/#{account.id}", "accounts/#{foreign.id}"), headers: headers,
         params: { recording_task: input }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(counts).to eq([0, 0, 0])
  end

  it 'does not gain current project create authority from listen, quality review or native administrator status' do
    member.update!(role: :administrator)
    role.update!(permissions: role.permissions - ['jrc_projects_task_create'])
    post_task
    expect(response).to have_http_status(:unauthorized)
    expect(counts).to eq([0, 0, 0])
  end

  it 'denies a formerly authorized origin after corporate coverage is withdrawn' do
    account.jrc_crm_user_business_units.where(user: actor).find_each { |coverage| coverage.update!(active: false) }
    post_task
    expect(response).to have_http_status(:not_found)
    expect(counts).to eq([0, 0, 0])
  end

  it 'does not reveal private target identifiers after native Project membership is removed' do
    post_task
    row = JrcContactCenter::RecordingTaskLink.where(account: account).sole
    project.project_members.where(account: account, user: actor).sole.destroy!
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').sole).to include('id' => row.id.to_s, 'target' => nil)
    expect(response.body).not_to include(project.name, input.fetch('task').fetch('title'), "\"project_id\"")
    expect(counts).to eq([1, 1, 1])
  end

  it 'paginates committed links by 20 without duplicates and allows safe navigation back to the first page' do
    21.times do |number|
      values = input.deep_dup.merge('request_id' => SecureRandom.uuid)
      values.fetch('task')['title'] = "SYNTHETIC page task #{number}"
      post_task(values)
      expect(response).to have_http_status(:ok)
    end
    get path, headers: headers, params: { page: 1 }, as: :json
    first = response.parsed_body
    expect(first.fetch('items').length).to eq(20)
    expect(first.fetch('meta')).to eq('page' => 1, 'per_page' => 20, 'total' => 21, 'pages' => 2)
    get path, headers: headers, params: { page: 2 }, as: :json
    last = response.parsed_body
    expect(last.fetch('items').length).to eq(1)
    expect(first.fetch('items').pluck('id') & last.fetch('items').pluck('id')).to be_empty
    get path, headers: headers, params: { page: 1 }, as: :json
    expect(response.parsed_body).to eq(first)
    expect(counts).to eq([21, 21, 21])
  end
  it 'rejects caller-supplied account/unit/actor authority and malformed command shapes without creating any destination' do
    invalid = [
      input.merge('account_id' => account.id.to_s, 'unit_id' => unit.id.to_s),
      input.merge('user_id' => actor.id.to_s),
      input.merge('request_id' => [request_id]),
      input.merge('task' => input.fetch('task').merge('created_by_id' => actor.id))
    ]
    invalid.each do |values|
      post_task(values)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(counts).to eq([0, 0, 0])
    end
  end

end

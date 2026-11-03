require 'rails_helper'

RSpec.describe 'NICO native HTTP execution after browser claim', type: :request do
  let(:account) { create(:account, custom_attributes: { 'nico_enabled' => true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:project) do
    JrcProjects::Project.create!(account: account, owner: admin, key: 'FENCE', name: 'Native project', status: 'planned', visibility: 'account')
  end
  let(:task) do
    JrcProjects::Task.create!(account: account, project: project, created_by: admin, title: 'Original',
      status: 'backlog', priority: 'medium', estimated_minutes: 0)
  end
  let(:operator) { JrcNico::OperatorSession.new(account: account, user: admin) }
  let(:command) do
    operator.ask(message: 'Synthetic task edit', request_id: SecureRandom.uuid, prepared: {
      'tool' => 'update_project_task', 'arguments' => { 'project_id' => project.id, 'task_id' => task.id,
        'lock_version' => task.lock_version, 'title' => 'Reviewed title' }
    })
  end
  let(:path) { "/api/v1/accounts/#{account.id}/projects/projects/#{project.id}/tasks/#{task.id}" }
  let(:body) { { task: { title: 'Reviewed title', lock_version: 0 } } }
  let(:native_headers) { headers.merge('X-JRC-Nico-Command-Id' => command.id.to_s, 'X-JRC-Nico-Contract' => 'nico-native-v1') }

  before { account.enable_features!('jrc_projects') }

  def claim_command
    operator.execute(command)
    expect(command.reload.status).to eq('browser_pending')
    post "/api/v1/accounts/#{account.id}/jrc_nico/operations/commands/#{command.id}/claim", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(command.reload.status).to eq('executing')
  end

  def make_pending(record, target_account: account, actor: admin)
    batch = JrcMigrations::Batch.create!(account: target_account, created_by: actor,
      source: 'nico_http', domain: 'project_tasks', source_digest: 'a' * 64)
    JrcMigrations::Mapping.create!(account: target_account, batch: batch, source: 'nico_http', domain: 'project_tasks',
      legacy_id: record.id.to_s, target_id: record.id, source_digest: 'a' * 64, target_digest: 'b' * 64, source_updated_at: Time.current)
  end

  it 'rejects revocation between a valid claim and the native effect' do
    claim_command
    make_pending(task)
    expect { patch path, params: body, headers: native_headers, as: :json }.not_to change { task.reload.title }
    expect(response).to have_http_status(:forbidden)
  end

  it 'keeps the native human edit available without a NICO execution context' do
    make_pending(task)
    patch path, params: body, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(task.reload.title).to eq('Reviewed title')
  end

  it 'binds the exact reviewed payload at the native endpoint' do
    claim_command
    expect do
      patch path, params: { task: { lock_version: 0, title: 'Altered after review' } }, headers: native_headers, as: :json
    end.not_to change { task.reload.title }
    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects another authenticated administrator using the command' do
    claim_command
    other = create(:user, account: account, role: :administrator)
    forged = other.create_new_auth_token.merge(native_headers.slice('X-JRC-Nico-Command-Id', 'X-JRC-Nico-Contract'))
    expect { patch path, params: body, headers: forged, as: :json }.not_to change { task.reload.title }
    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects reuse in another Account even when the same actor is a native administrator there' do
    claim_command
    foreign = create(:account)
    foreign.enable_features!('jrc_projects')
    create(:account_user, account: foreign, user: admin, role: :administrator)
    foreign_project = JrcProjects::Project.create!(account: foreign, owner: admin, key: 'OTHER',
      name: 'Other native project', status: 'planned', visibility: 'account')
    foreign_task = JrcProjects::Task.create!(account: foreign, project: foreign_project, created_by: admin,
      title: 'Other original', status: 'backlog', priority: 'medium', estimated_minutes: 0)
    foreign_path = "/api/v1/accounts/#{foreign.id}/projects/projects/#{foreign_project.id}/tasks/#{foreign_task.id}"
    expect { patch foreign_path, params: body, headers: native_headers, as: :json }.not_to change { foreign_task.reload.title }
    expect(response).to have_http_status(:forbidden)
  end

  it 'consumes a successful execution once, independently of the native optimistic lock' do
    claim_command
    patch path, params: body, headers: native_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(task.reload.title).to eq('Reviewed title')
    patch path, params: body, headers: native_headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(task.reload.lock_version).to eq(1)
  end

  it 'rejects commands whose reviewed arguments changed after claim' do
    claim_command
    command.update!(arguments: command.arguments.merge('title' => 'Changed command'))
    expect do
      patch path, params: { task: { title: 'Changed command', lock_version: 0 } }, headers: native_headers, as: :json
    end.not_to change { task.reload.title }
    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects an expired context at the native endpoint' do
    claim_command
    travel 3.minutes do
      expect { patch path, params: body, headers: native_headers, as: :json }.not_to change { task.reload.title }
      expect(response).to have_http_status(:forbidden)
    end
  end

  it 'rolls back a native validation failure without claiming success or allowing a changed payload' do
    command
    command.update!(arguments: command.arguments.merge('title' => ''))
    claim_command
    rejected_body = { task: { title: '', lock_version: 0 } }
    expect { patch path, params: rejected_body, headers: native_headers, as: :json }.not_to change { task.reload.title }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(command.reload.status).to eq('executing')
    contract = command.execution_context.fetch('native_browser_command')
    expect(contract['consumed_at']).to be_nil
    patch path, params: rejected_body, headers: native_headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    patch path, params: body, headers: native_headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(task.reload.lock_version).to eq(0)
  end

  it 'consumes a native denied attempt without recording success and rejects replay' do
    claim_command
    # Exercise the native around-action's handled 403 after a valid preflight;
    # the separate two-connection case covers actual role revocation timing.
    allow_any_instance_of(JrcProjects::Api::V1::TasksController).to receive(:authorize_capability!).and_raise(Pundit::NotAuthorizedError)
    expect { patch path, params: body, headers: native_headers, as: :json }.not_to change { task.reload.title }
    expect(response).to have_http_status(:forbidden)
    expect(command.reload.status).to eq('executing')
    consumed_at = command.execution_context.dig('native_browser_command', 'consumed_at')
    expect(consumed_at).to be_present
    expect(command.execution_context.dig('native_browser_command', 'response_status')).to eq(403)
    patch path, params: body, headers: native_headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(command.reload.execution_context.dig('native_browser_command', 'consumed_at')).to eq(consumed_at)
    expect(task.reload.lock_version).to eq(0)
    expect(JrcProjects::AuditEvent.where(account_id: account.id, action: 'projects.task.updated')).not_to exist
  end

  it 'rejects browser-reported success before the fenced native request ran' do
    claim_command
    post "/api/v1/accounts/#{account.id}/jrc_nico/operations/commands/#{command.id}/receipt",
      params: { status: 'succeeded', detail: 'Unverified browser claim' }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(command.reload.status).to eq('executing')
    expect(command.execution_context.dig('native_browser_command', 'consumed_at')).to be_nil
    expect(task.reload.lock_version).to eq(0)
  end

  it 'rejects browser-reported success after a consumed native denial' do
    claim_command
    allow_any_instance_of(JrcProjects::Api::V1::TasksController).to receive(:authorize_capability!).and_raise(Pundit::NotAuthorizedError)
    patch path, params: body, headers: native_headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(command.reload.execution_context.dig('native_browser_command', 'consumed_at')).to be_present
    post "/api/v1/accounts/#{account.id}/jrc_nico/operations/commands/#{command.id}/receipt",
      params: { status: 'succeeded', detail: 'False success after denial' }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(command.reload.status).to eq('executing')
    expect(task.reload.lock_version).to eq(0)
    expect(JrcProjects::AuditEvent.where(account_id: account.id, action: 'projects.task.updated')).not_to exist
  end

  it 'accepts browser acknowledgement after the exact local fenced request returned success' do
    claim_command
    patch path, params: body, headers: native_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(command.reload.execution_context.dig('native_browser_command', 'response_status')).to eq(200)
    post "/api/v1/accounts/#{account.id}/jrc_nico/operations/commands/#{command.id}/receipt",
      params: { status: 'succeeded', detail: 'Native edit acknowledged' }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(command.reload.status).to eq('succeeded')
    expect(task.reload).to have_attributes(title: 'Reviewed title', lock_version: 1)
    expect(JrcProjects::AuditEvent.where(account_id: account.id, action: 'projects.task.updated').count).to eq(1)
  end
end

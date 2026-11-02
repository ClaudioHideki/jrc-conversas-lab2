# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk screen editing, withdrawal and filtered timelines', type: :request do
  include_context 'JRC Service Desk domain'
  let(:ticket) { sd_ticket }
  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/tickets/#{ticket.id}" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:notes) { JrcServiceDesk::AddNoteService.new(user_context: sd_context) }
  let(:tasks) { JrcServiceDesk::CreateTaskService.new(user_context: sd_context) }

  it 'denies ticket deletion to an ordinary agent even when that agent can edit' do
    delete base, params: { expected_lock_version: ticket.lock_version, reason: 'Cadastro duplicado' }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(ticket.ticket_events.where(event_type: 'ticket_deleted')).to be_empty
    get base, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('ticket', 'permissions', 'destroy')).to be(false)
  end

  it 'logically deletes an authorized ticket and removes it from lists, cockpit and exports without deleting its history' do
    sd_as_admin!
    note = notes.call(ticket_id: ticket.id, attributes: { body: 'Preservar evidência interna' }, idempotency_key: 'original-evidence')
    delete base, params: { expected_lock_version: ticket.lock_version, reason: 'Chamado cadastrado em duplicidade' }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.values_at('applied', 'operation')).to eq([true, 'delete'])
    expect(JrcServiceDesk::Ticket.exists?(ticket.id)).to be(true)
    expect(JrcServiceDesk::TicketNote.find(note.id).body).to eq('Preservar evidência interna')
    expect(ticket.ticket_events.find_by!(event_type: 'ticket_deleted').data['reason']).to eq('Chamado cadastrado em duplicidade')
    [base, "#{base}/cockpit", "#{base}/export"].each do |path|
      get path, headers: headers
      expect(response).to have_http_status(:not_found)
    end
    get "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/tickets", headers: headers
    expect(response.parsed_body['items']).to be_empty
  end

  it 'does not delete a ticket from a stale version or without a reason' do
    sd_as_admin!
    delete base, params: { expected_lock_version: ticket.lock_version + 1, reason: 'Cadastro duplicado' }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    delete base, params: { expected_lock_version: ticket.lock_version, reason: '' }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(ticket.ticket_events.where(event_type: 'ticket_deleted')).to be_empty
  end

  it 'requires Projects links to be removed before deleting a ticket or changing its customer context' do
    sd_as_admin!
    sd_account.enable_features!('jrc_projects')
    project = JrcProjects::Projects::Create.call(account: sd_account, actor: sd_user,
                                                 attributes: { name: 'Projeto vinculado', contact_id: sd_contact.id }, idempotency_key: 'linked-project')
    link = JrcOperations::Linker.new(account_user: sd_account_user).create!(attributes: { project_id: project.id, ticket_id: ticket.id })
    replacement = create(:contact, account: sd_account)
    patch base, params: { ticket: { requester_id: replacement.id }, expected_lock_version: ticket.lock_version }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['code']).to eq('linked_context_conflict')
    expect(ticket.reload.requester_id).to eq(sd_contact.id)
    delete base, params: { expected_lock_version: ticket.lock_version, reason: 'Chamado duplicado' }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['code']).to eq('deletion_blocked')
    expect(ticket.ticket_events.where(event_type: 'ticket_deleted')).to be_empty
    delete "/api/v1/accounts/#{sd_account.id}/operations/links/#{link.id}", params: { ticket_id: ticket.id }, headers: headers, as: :json
    expect(response).to have_http_status(:no_content)
    delete base, params: { expected_lock_version: ticket.lock_version, reason: 'Chamado duplicado' }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(project.reload).to be_present
  end

  it 'revalidates the requester against the current account and records the persisted change' do
    replacement = create(:contact, account: sd_account)
    patch base, params: { ticket: { requester_id: replacement.id }, expected_lock_version: ticket.lock_version }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(ticket.reload.requester).to eq(replacement)
    expect(ticket.ticket_events.last.data['requester_id']).to eq([sd_contact.id, replacement.id])
    foreign = create(:contact, account: sd_foreign_account)
    patch base, params: { ticket: { requester_id: foreign.id }, expected_lock_version: ticket.lock_version }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(ticket.reload.requester).to eq(replacement)
  end

  it 'edits a task title and description and excludes a deleted task from cockpit and operations board' do
    task = tasks.call(ticket_id: ticket.id, attributes: { title: 'Título inicial' }, idempotency_key: 'task-edit')
    path = "#{base}/tasks/#{task.id}"
    patch path, params: { task: { title: 'Título corrigido', description: 'Procedimento atualizado' }, expected_lock_version: task.lock_version },
                headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(task.reload.title).to eq('Título corrigido')
    delete path, params: { expected_lock_version: task.lock_version, reason: 'Tarefa duplicada' }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(JrcServiceDesk::TicketTask.exists?(task.id)).to be(true)
    get "#{base}/cockpit", headers: headers
    expect(response.parsed_body.dig('cockpit', 'tasks')).to be_empty
    get "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/board", params: { kind: 'tasks' }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['items']).to be_empty
  end

  it 'preserves completed task timestamps and does not replay completion effects when correcting text' do
    task = tasks.call(ticket_id: ticket.id, attributes: { title: 'Concluir revisão' }, idempotency_key: 'completed-task-edit')
    service = JrcServiceDesk::UpdateTaskService.new(user_context: sd_context)
    service.call(ticket_id: ticket.id, task_id: task.id, attributes: { status: 'completed' }, expected_lock_version: task.lock_version)
    completed_at = task.reload.completed_at
    expect(JrcServiceDesk::TaskProgression).not_to receive(:new)
    patch "#{base}/tasks/#{task.id}", params: { task: { title: 'Revisão concluída' }, expected_lock_version: task.lock_version },
                                    headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(task.reload.completed_at).to eq(completed_at)
  end

  it 'corrects an internal note through a new immutable version and never requests external delivery' do
    note = notes.call(ticket_id: ticket.id, attributes: { body: 'Diagnóstico inicial' }, idempotency_key: 'note-original')
    payload = { note: { body: 'Diagnóstico corrigido' }, reason: 'Correção de digitação' }
    patch "#{base}/notes/#{note.id}", params: payload, headers: headers.merge('Idempotency-Key' => 'note-correction'), as: :json
    expect(response).to have_http_status(:ok)
    replacement = JrcServiceDesk::TicketNote.find(response.parsed_body['result_id'])
    expect(replacement.previous_note_id).to eq(note.id)
    expect(replacement.notification_channels).to eq([])
    expect(note.reload.body).to eq('Diagnóstico inicial')
    get "#{base}/notes", headers: headers
    expect(response.parsed_body['items'].map { |row| row['body'] }).to eq(['Diagnóstico corrigido'])
    expect do
      patch "#{base}/notes/#{note.id}", params: payload, headers: headers.merge('Idempotency-Key' => 'note-correction'), as: :json
    end.not_to change(JrcServiceDesk::TicketNote, :count)
    expect(response).to have_http_status(:ok)
    expect(JrcServiceDesk::NotificationDelivery.count).to eq(0)
  end

  it 'denies edits and withdrawal of another agents note' do
    author = create(:account_user, account: sd_account, role: :agent)
    grant = create(:jrc_sd_membership, unit: sd_unit, account_user: author)
    ticket.update!(assignee_membership: grant)
    context = { account: sd_account, account_user: author, user: author.user }
    note = JrcServiceDesk::AddNoteService.new(user_context: context).call(
      ticket_id: ticket.id, attributes: { body: 'Nota de outro autor' }, idempotency_key: 'other-author'
    )
    delete "#{base}/notes/#{note.id}", params: { reason: 'Tentativa sem permissão' }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(ticket.ticket_events.where(event_type: 'note_withdrawn')).to be_empty
  end

  it 'withdraws an attachment without purging the original blob and denies both operator download routes' do
    file = fixture_file_upload(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt'), 'text/plain')
    post "#{base}/interactions", params: { note: { body: 'Anexo interno' }, files: [file] }, headers: headers.merge('Idempotency-Key' => 'withdraw-file')
    expect(response).to have_http_status(:created)
    note = ticket.ticket_notes.last
    attachment = note.files.first
    attachment.blob.update!(metadata: { 'service_desk_scan_state' => 'clean' })
    notes.call(ticket_id: ticket.id, attributes: { body: 'Nota mais recente sem arquivo' }, idempotency_key: 'no-file-note')
    get "#{base}/timeline", params: { view: 'files', per_page: 1 }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('timeline', 'items').pluck('id')).to eq([note.id.to_s])
    expect(response.parsed_body.dig('timeline', 'items', 0, 'attachments', 0, 'content_type')).to eq('text/plain')
    path = "#{base}/notes/#{note.id}/attachments/#{attachment.id}"
    delete path, params: { reason: 'Anexo substituído' }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(ActiveStorage::Blob.exists?(attachment.blob_id)).to be(true)
    get path, headers: headers
    expect(response).to have_http_status(:not_found)
    get "#{base}/timeline/note/#{note.id}/attachments/#{attachment.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    get "#{base}/notes", headers: headers
    expect(response.parsed_body['items'].first['attachments']).to eq([])
    get "#{base}/timeline", params: { view: 'files', per_page: 1 }, headers: headers
    expect(response.parsed_body.dig('timeline', 'items')).to eq([])
  end

  it 'applies history author, type and inclusive dates before pagination and rejects a changed filter cursor' do
    actor = create(:account_user, account: sd_account, role: :agent)
    grant = create(:jrc_sd_membership, unit: sd_unit, account_user: actor)
    rows = [Time.zone.local(2026, 10, 22), Time.zone.local(2026, 10, 22, 23, 59, 59), Time.zone.local(2026, 10, 23)].map do |at|
      ticket.ticket_events.create!(account: sd_account, unit: sd_unit, actor_membership: sd_membership,
                                   event_type: 'ticket_updated', data: {}, visibility: 'internal', created_at: at)
    end
    ticket.ticket_events.create!(account: sd_account, unit: sd_unit, actor_membership: grant,
                                 event_type: 'ticket_updated', data: {}, visibility: 'internal', created_at: Time.zone.local(2026, 10, 22, 12))
    query = { view: 'history', author_id: sd_account_user.id, event_type: 'ticket_updated',
              date_from: '2026-10-22', date_to: '2026-10-22', per_page: 1 }
    get "#{base}/timeline", params: query, headers: headers
    expect(response).to have_http_status(:ok)
    page = response.parsed_body['timeline']
    expect(page['items'].pluck('id')).to eq([rows[1].id.to_s])
    get "#{base}/timeline", params: query.merge(cursor: page['next_cursor']), headers: headers
    expect(response.parsed_body.dig('timeline', 'items').pluck('id')).to eq([rows[0].id.to_s])
    get "#{base}/timeline", params: query.merge(date_to: '2026-10-23', cursor: page['next_cursor']), headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'filters internal notes before pagination and binds the cursor to the selected tab' do
    sd_as_admin!
    internal = Array.new(3) { |i| notes.call(ticket_id: ticket.id, attributes: { body: "Nota interna #{i}" }, idempotency_key: "filtered-note-#{i}") }
    attributes = { body: 'Resposta pública', visibility: 'public_without_notification' }
    context = JrcServiceDesk::OperationalContext.new(sd_context)
    receipt = JrcServiceDesk::InteractionPreview.new(ticket: ticket, context: context).call(attributes: attributes).fetch(:receipt)
    notes.call(ticket_id: ticket.id, attributes: attributes, preview_receipt: receipt, idempotency_key: 'public-for-filter')
    get "#{base}/timeline", params: { view: 'notes', per_page: 2 }, headers: headers
    expect(response).to have_http_status(:ok)
    page = response.parsed_body['timeline']
    expect(page['items'].map { |row| row['id'] }).to eq(internal.last(2).reverse.map { |row| row.id.to_s })
    get "#{base}/timeline", params: { view: 'notes', per_page: 2, cursor: page['next_cursor'] }, headers: headers
    expect(response.parsed_body.dig('timeline', 'items').map { |row| row['id'] }).to eq([internal.first.id.to_s])
    get "#{base}/timeline", params: { view: 'conversations', cursor: page['next_cursor'] }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    get "#{base}/timeline", params: { view: 'conversations' }, headers: headers
    expect(response.body).to include('Resposta pública')
    expect(response.body).not_to include('Nota interna')
  end

  it 'applies team and inclusive date filters to the list and dashboard using the same authorized cohort' do
    sd_as_admin!
    team = create(:team, account: sd_account)
    selected = sd_ticket(team: team, created_at: Time.zone.local(2026, 10, 22, 12))
    sd_ticket(created_at: Time.zone.local(2026, 10, 21, 12))
    query = { team_id: team.id, created_from: '2026-10-22', created_to: '2026-10-22' }
    get "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/tickets", params: query, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['items'].map { |row| row['id'] }).to eq([selected.id.to_s])
    get "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/dashboard", params: query, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('dashboard', 'filters', 'team_id')).to eq(team.id)
    get "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/tickets", params: { created_from: '2026-10-23', created_to: '2026-10-22' }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end
end

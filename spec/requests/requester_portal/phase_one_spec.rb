# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Requester portal Phase 1 over the native Service Desk', type: :request do
  include_context 'JRC Service Desk domain'

  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'Synthetic customer A') }
  let(:sd_contact) do
    create(:contact, account: sd_account, company_id: company.id, name: 'Synthetic requester', email: 'requester-a@example.test',
                     phone_number: '+5511999990011', identifier: SecureRandom.uuid)
  end
  let(:portal_user) { create(:user, email: 'portal-a@example.test', password: 'Portal@Test123') }
  let(:widget) { create(:channel_widget, account: sd_account) }
  let(:identity) { create(:contact_inbox, contact: sd_contact, inbox: widget.inbox, hmac_verified: true) }
  let(:grant) do
    JrcServiceDesk::PortalGrant.create!(account: sd_account, user: portal_user, company: company, contact: sd_contact,
                                      inbox: widget.inbox, contact_inbox: identity, granted_by: sd_user, active: true)
  end
  let(:service) do
    JrcServiceDesk::Service.create!(account: sd_account, unit: sd_unit, code: 'phase1-portal', name: 'Synthetic support', active: true,
                                    default_priority: sd_priority, portal_inbox: widget.inbox, portal_execution_membership: sd_membership,
                                    portal_enabled: true)
  end
  let(:creation) do
    { service_id: service.id.to_s, service_revision: JrcServiceDesk::ConfigurationResources.revision('services', service),
      title: 'Synthetic portal ticket', description: 'Public customer evidence', service_fields: {} }
  end
  let(:native_headers) { portal_user.create_new_auth_token }
  let(:write_headers) { { 'Idempotency-Key' => 'phase1-ticket-create' } }

  before do
    sd_account.enable_features!('jrc_customer_master')
    sd_account.update!(internal_attributes: sd_account.internal_attributes.merge('requester_portal_enabled' => true))
    sd_as_admin!
    sd_status
    grant
    post '/portal/session', params: {}, headers: native_headers, as: :json
    code = response.parsed_body.is_a?(Hash) ? response.parsed_body['code'] : 'non_json'
    expect(response).to have_http_status(:ok), "Native cookie bridge rejected: status=#{response.status}, code=#{code}"
  end

  it 'uses native authentication and an HttpOnly bridge without exposing native or widget credentials' do
    expect(portal_user.account_users).to be_empty
    cookie = Array(response.headers['Set-Cookie']).find { |value| value.start_with?('_jrc_requester_portal=') }
    expect(cookie.present?).to be(true)
    expect(cookie.split(';').drop(1).map(&:strip)).to include('httponly', 'samesite=lax')
    expect(response.headers['access-token']).to be_nil
    expect(response.body).not_to include('access-token', 'hmac_token', identity.source_id)
    get '/portal/session'
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('context', 'id')).to eq(grant.id.to_s)
    expect(response.parsed_body.dig('context', 'contact', 'phone_number')).to eq(sd_contact.phone_number)
  end

  it 'blocks the operational shell and direct operational APIs for a requester-only native User' do
    get "/app/accounts/#{sd_account.id}/dashboard"
    expect(response).to have_http_status(:forbidden)
    get "/api/v1/accounts/#{sd_account.id}/contacts", headers: native_headers
    expect([401, 403]).to include(response.status)
    expect(response.body).not_to include(sd_contact.email)
  end

  it 'creates exactly one real ticket, uses catalogue priority and preserves master contact opening data' do
    expect do
      post '/portal/api/chamados', params: { ticket: creation }, headers: write_headers, as: :json
    end.to change(JrcServiceDesk::Ticket, :count).by(1)
    expect(response).to have_http_status(:created)
    ticket = JrcServiceDesk::Ticket.find(response.parsed_body.dig('ticket', 'id'))
    expect(ticket.origin_channel).to eq('portal')
    expect(ticket.requester).to eq(sd_contact)
    expect(ticket.company_id).to eq(company.id)
    expect(ticket.priority).to eq(sd_priority)
    expect(ticket.created_by_membership).to eq(sd_membership)
    request = JrcServiceDesk::PortalRequest.find_by!(ticket: ticket)
    expect(request.message.sender).to eq(sd_contact)
    expect(request.message.incoming?).to be(true)
    expect(request.message.content_attributes['service_desk_origin']).to eq('portal')
    expect(request.service_snapshot['requester_snapshot']).to include('email' => sd_contact.email, 'phone_number' => sd_contact.phone_number)
    expect do
      post '/portal/api/chamados', params: { ticket: creation }, headers: write_headers, as: :json
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response.parsed_body.dig('ticket', 'number')).to eq(ticket.id.to_s)
    get "/portal/api/chamados/#{ticket.id}"
    expect(response.parsed_body['sla']).to be_empty
    expect(response.parsed_body['can_reply']).to be(true)
  end

  it 'rejects arbitrary priority, requester, tenant, assignee and service configuration fields' do
    %w[priority_id requester_id account_id company_id unit_id assignee_account_user_id status_id category_id].each do |field|
      post '/portal/api/chamados', params: { ticket: creation.merge(field => '1') }, headers: write_headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(JrcServiceDesk::PortalRequest.where(account: sd_account)).to be_empty
  end

  it 'requires the current master email, mobile and description and never changes master identity from browser data' do
    sd_contact.update!(phone_number: nil)
    post '/portal/api/chamados', params: { ticket: creation }, headers: write_headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('master_profile_incomplete')
    expect(sd_contact.reload.email).to eq('requester-a@example.test')
    expect(JrcServiceDesk::PortalRequest.where(account: sd_account)).to be_empty
  end

  it 'rejects an unpublished catalogue and an altered idempotent submission' do
    fields = creation
    service.update!(portal_enabled: false)
    post '/portal/api/chamados', params: { ticket: fields }, headers: write_headers, as: :json
    expect(response).to have_http_status(:not_found)
    service.update!(portal_enabled: true)
    fields[:service_revision] = JrcServiceDesk::ConfigurationResources.revision('services', service)
    post '/portal/api/chamados', params: { ticket: fields }, headers: write_headers, as: :json
    expect(response).to have_http_status(:created)
    post '/portal/api/chamados', params: { ticket: fields.merge(title: 'Changed attempt') }, headers: write_headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(JrcServiceDesk::PortalRequest.where(account: sd_account).count).to eq(1)
  end

  context 'with a real customer ticket and native conversation' do
    let(:ticket) { sd_ticket(service: service) }
    let(:conversation) { create(:conversation, account: sd_account, inbox: widget.inbox, contact: sd_contact, contact_inbox: identity) }

    before { create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation) }

    it 'returns only public notes and public native replies; private notes cannot be fetched indirectly or by a direct note URL' do
      public_note = create(:jrc_sd_note, ticket: ticket, visibility: 'public_without_notification', body: 'Visible support publication')
      private_note = create(:jrc_sd_note, ticket: ticket, body: 'Internal diagnostics never public')
      create(:message, account: sd_account, inbox: widget.inbox, conversation: conversation, sender: sd_user,
                       message_type: :outgoing, private: false, content: 'Native public response')
      create(:message, account: sd_account, inbox: widget.inbox, conversation: conversation, sender: sd_user,
                       message_type: :outgoing, private: true, content: 'Private native response')
      create(:message, account: sd_account, inbox: widget.inbox, conversation: conversation, sender: sd_contact,
                       message_type: :incoming, private: true, content: 'Private incoming response',
                       content_attributes: { 'service_desk_ticket_id' => ticket.id.to_s })
      get "/portal/api/chamados/#{ticket.id}"
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['notes'].pluck('id')).to eq([public_note.id.to_s])
      expect(response.parsed_body['public_messages'].pluck('body')).to include('Native public response')
      expect(response.body).not_to include(private_note.body, 'Private native response', 'Private incoming response',
                                           'actor_membership', 'routing', 'source_snapshot')
      get "/portal/api/chamados/#{ticket.id}/notas/#{private_note.id}/anexos/1"
      expect(response).to have_http_status(:not_found)
    end

    it 'records one native incoming public reply under the actual requester and replays without duplication' do
      values = { body: 'Synthetic customer answer', conversation_id: conversation.id }
      headers = { 'Idempotency-Key' => 'phase1-reply' }
      expect do
        2.times { post "/portal/api/chamados/#{ticket.id}/mensagens", params: values, headers: headers, as: :json }
      end.to change(Message, :count).by(1)
      expect(response).to have_http_status(:created)
      message = Message.find(response.parsed_body['message_id'])
      expect(message.sender).to eq(sd_contact)
      expect(message.conversation).to eq(conversation)
      expect(message.private?).to be(false)
      get "/portal/api/chamados/#{ticket.id}"
      expect(response.parsed_body['replies'].pluck('body')).to include(values[:body])
    end

    it 'paginates and filters only authorized ticket records' do
      get '/portal/api/chamados', params: { q: ticket.id.to_s, phase: ticket.status.phase, from: Date.current.iso8601, page: '1' }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['tickets'].pluck('id')).to eq([ticket.id.to_s])
      expect(response.parsed_body.values_at('page', 'per_page', 'total')).to eq([1, 20, 1])
      get '/portal/api/chamados', params: { account_id: sd_foreign_account.id }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'denies ticket/reply/attachment IDOR for another requester in the same company and another company/account' do
      other_contact = create(:contact, account: sd_account, company_id: company.id)
      other_ticket = sd_ticket(requester: other_contact, title: 'Other requester confidential')
      other_identity = create(:contact_inbox, contact: other_contact, inbox: widget.inbox, hmac_verified: true)
      other_conversation = create(:conversation, account: sd_account, inbox: widget.inbox, contact: other_contact, contact_inbox: other_identity)
      create(:jrc_sd_conversation_link, ticket: other_ticket, conversation: other_conversation)
      foreign = create(:jrc_sd_ticket, unit: sd_foreign_unit)
      company_b = JrcCustomers::Company.create!(account: sd_account, name: 'Synthetic company B')
      contact_b = create(:contact, account: sd_account, company_id: company_b.id)
      identity_b = create(:contact_inbox, contact: contact_b, inbox: widget.inbox, hmac_verified: true)
      conversation_b = create(:conversation, account: sd_account, inbox: widget.inbox, contact: contact_b, contact_inbox: identity_b)
      company_ticket = sd_ticket(requester: contact_b, title: 'Other company confidential')
      create(:jrc_sd_conversation_link, ticket: company_ticket, conversation: conversation_b)
      [other_ticket, company_ticket, foreign].each do |denied|
        get "/portal/api/chamados/#{denied.id}"
        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to include(denied.title)
        post "/portal/api/chamados/#{denied.id}/mensagens", params: { body: 'IDOR', conversation_id: other_conversation.id },
                                                         headers: { 'Idempotency-Key' => 'idor-reply' }, as: :json
        expect(response).to have_http_status(:not_found)
        get "/portal/api/chamados/#{denied.id}/mensagens/1/anexos/1"
        expect(response).to have_http_status(:not_found)
      end
    end

    it 'allows only enumerated manager visibility, and never writes as another native customer' do
      other_contact = create(:contact, account: sd_account, company_id: company.id)
      other_identity = create(:contact_inbox, contact: other_contact, inbox: widget.inbox, hmac_verified: true)
      other_conversation = create(:conversation, account: sd_account, inbox: widget.inbox, contact: other_contact, contact_inbox: other_identity)
      other_ticket = sd_ticket(requester: other_contact)
      create(:jrc_sd_conversation_link, ticket: other_ticket, conversation: other_conversation)
      grant.update!(role: 'manager')
      get "/portal/api/chamados/#{other_ticket.id}"
      expect(response).to have_http_status(:not_found)
      grant.update!(visible_contact_ids: [other_contact.id])
      get "/portal/api/chamados/#{other_ticket.id}"
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['can_reply']).to be(false)
      post "/portal/api/chamados/#{other_ticket.id}/mensagens", params: { body: 'Impersonation', conversation_id: other_conversation.id },
                                                             headers: { 'Idempotency-Key' => 'manager-reply' }, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'guards public/internal attachments and signed native blob URLs while preserving authorized operational access' do
      file = fixture_file_upload(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt'), 'text/plain')
      note = create(:jrc_sd_note, ticket: ticket, body: 'Private attachment note', files: [file])
      blob_path = Rails.application.routes.url_helpers.rails_blob_path(note.files.first, only_path: true)
      get blob_path
      expect(response).to have_http_status(:not_found)
      get blob_path, headers: sd_user.create_new_auth_token
      # Portal identity takes precedence over arbitrary bearer headers while a
      # requester cookie exists; use a separate native operator HTTP session.
      operator_session = ActionDispatch::Integration::Session.new(Rails.application)
      operator_session.get blob_path, headers: sd_user.create_new_auth_token
      expect(operator_session.response).to have_http_status(:not_found)
      note.files.first.blob.update!(metadata: { 'service_desk_scan_state' => 'clean' })
      operator_session.get blob_path, headers: sd_user.create_new_auth_token
      expect(operator_session.response).to have_http_status(:ok)
      expect(operator_session.response.headers['Location']).to be_nil
      expect(operator_session.response.body).to include('Project attachment test')

      team = create(:team, account: sd_account)
      queue = create(:jrc_sd_queue, unit: sd_unit, team: team)
      ticket.update!(queue: queue, team: team)
      sd_membership.update!(restricted_supervision: true,
                            supervision_grants: [{ 'queue_id' => queue.id, 'team_id' => team.id, 'permissions' => ['tickets_view'] }])
      operator_session.get blob_path, headers: sd_user.create_new_auth_token
      expect(operator_session.response).to have_http_status(:not_found)
      sd_membership.update!(restricted_supervision: false, supervision_grants: [])

      post "/portal/api/chamados/#{ticket.id}/mensagens", params: { body: 'Public customer file', conversation_id: conversation.id, files: [file] },
                                                         headers: { 'Idempotency-Key' => 'phase1-file' }
      expect(response).to have_http_status(:created)
      message = Message.find(response.parsed_body['message_id'])
      attachment = message.attachments.first
      path = "/portal/api/chamados/#{ticket.id}/mensagens/#{message.id}/anexos/#{attachment.id}"
      get path
      expect(response).to have_http_status(:conflict)
      attachment.file.blob.update!(metadata: { 'service_desk_scan_state' => 'clean' })
      get path
      expect(response).to have_http_status(:ok)
      get Rails.application.routes.url_helpers.rails_blob_path(attachment.file, only_path: true)
      expect(response).to have_http_status(:ok)
      expect(response.headers['Location']).to be_nil
      grant.update!(active: false)
      get path
      expect(response).to have_http_status(:forbidden)
      get Rails.application.routes.url_helpers.rails_blob_path(attachment.file, only_path: true)
      expect(response).to have_http_status(:not_found)
    end

    it 'rechecks scan and native conversation permissions on direct Message attachments' do
      message = create(:message, account: sd_account, inbox: widget.inbox, conversation: conversation, sender: sd_user,
                                 message_type: :outgoing, private: false, content: 'Public native evidence')
      attachment = message.attachments.create!(account: sd_account, file_type: :file,
                                               file: fixture_file_upload(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt'), 'text/plain'))
      path = Rails.application.routes.url_helpers.rails_blob_path(attachment.file, only_path: true)
      operator = ActionDispatch::Integration::Session.new(Rails.application)
      operator.get path, headers: sd_user.create_new_auth_token
      expect(operator.response).to have_http_status(:not_found)
      attachment.file.blob.update!(metadata: { 'service_desk_scan_state' => 'clean' })
      operator.get path, headers: sd_user.create_new_auth_token
      expect(operator.response).to have_http_status(:ok)
      expect(operator.response.headers['Location']).to be_nil
      team = create(:team, account: sd_account)
      queue = create(:jrc_sd_queue, unit: sd_unit, team: team)
      ticket.update!(queue: queue, team: team)
      sd_membership.update!(restricted_supervision: true,
                            supervision_grants: [{ 'queue_id' => queue.id, 'team_id' => team.id, 'permissions' => ['tickets_view'] }])
      operator.get path, headers: sd_user.create_new_auth_token
      expect(operator.response).to have_http_status(:not_found)
      get path
      expect(response).to have_http_status(:ok)
      grant.update!(active: false)
      get path
      expect(response).to have_http_status(:not_found)
    end

    it 'applies the current portal identity to signed proxy and default-disk URLs for a protected blob' do
      file = fixture_file_upload(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt'), 'text/plain')
      note = create(:jrc_sd_note, ticket: ticket, visibility: 'public_without_notification', body: 'Public file', files: [file])
      blob = note.files.first.blob
      blob.update!(metadata: { 'service_desk_scan_state' => 'clean' })
      encoded = ActiveStorage.verifier.generate({ key: blob.key }, purpose: :blob_key)
      paths = [Rails.application.routes.url_helpers.rails_service_blob_proxy_path(blob.signed_id, blob.filename, only_path: true),
               Rails.application.routes.url_helpers.rails_disk_service_path(encoded_key: encoded, filename: blob.filename, only_path: true)]
      visitor = ActionDispatch::Integration::Session.new(Rails.application)
      paths.each do |path|
        visitor.get path
        expect(visitor.response).to have_http_status(:not_found)
        get path
        expect(response).to have_http_status(:ok)
        expect(response.headers['Location']).to be_nil
      end
      grant.update!(active: false)
      paths.each do |path|
        get path
        expect(response).to have_http_status(:not_found)
      end
    end

    it 'gates recordings only for calls explicitly linked to Service Desk conversations and never grants them to portal identities' do
      skip 'Native enterprise calls unavailable' unless defined?(::Call)

      call = create(:call, conversation: conversation, accepted_by_agent: sd_user)
      call.recording.attach(io: StringIO.new('Synthetic local recording'), filename: 'synthetic-recording.wav', content_type: 'audio/wav')
      path = Rails.application.routes.url_helpers.rails_blob_path(call.recording, only_path: true)
      operator = ActionDispatch::Integration::Session.new(Rails.application)
      operator.get path, headers: sd_user.create_new_auth_token
      expect(operator.response).to have_http_status(:not_found)
      call.recording.blob.update!(metadata: { 'service_desk_scan_state' => 'clean' })
      expect(call.recording.blob.download).to eq('Synthetic local recording')
      allowed = JrcServiceDesk::ProtectedBlobAccess.new(blob: call.recording.blob, user: sd_user).allowed?
      expect(allowed).to be(true)
      operator.get path, headers: sd_user.create_new_auth_token
      expect(operator.response).to have_http_status(:ok)
      expect(operator.response.headers['Location']).to be_nil
      get path
      expect(response).to have_http_status(:not_found)
      team = create(:team, account: sd_account)
      queue = create(:jrc_sd_queue, unit: sd_unit, team: team)
      ticket.update!(queue: queue, team: team)
      sd_membership.update!(restricted_supervision: true,
                            supervision_grants: [{ 'queue_id' => queue.id, 'team_id' => team.id, 'permissions' => ['tickets_view'] }])
      operator.get path, headers: sd_user.create_new_auth_token
      expect(operator.response).to have_http_status(:not_found)
      other_conversation = create(:conversation, account: sd_account, inbox: widget.inbox, contact: sd_contact, contact_inbox: identity)
      other_call = create(:call, conversation: other_conversation, accepted_by_agent: sd_user)
      other_call.recording.attach(io: StringIO.new('Unrelated native recording'), filename: 'unrelated-recording.wav', content_type: 'audio/wav')
      visitor = ActionDispatch::Integration::Session.new(Rails.application)
      visitor.get Rails.application.routes.url_helpers.rails_blob_path(other_call.recording, only_path: true)
      expect(visitor.response).to have_http_status(:redirect)
    end
  end

  it 'revokes an encrypted session after native token expiration and logout' do
    client = native_headers.fetch('client')
    tokens = portal_user.reload.tokens
    tokens[client]['expiry'] = 1.minute.ago.to_i
    portal_user.update!(tokens: tokens)
    get '/portal/api/catalogo'
    expect(response).to have_http_status(:unauthorized)
    fresh_headers = portal_user.create_new_auth_token
    post '/portal/session', params: {}, headers: fresh_headers, as: :json
    expect(response).to have_http_status(:ok)
    delete '/portal/session'
    expect(response).to have_http_status(:ok)
    get '/portal/api/catalogo'
    expect(response).to have_http_status(:unauthorized)
    get '/portal/api/catalogo', headers: fresh_headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'reuses a valid native dashboard identity without creating or broadening operational membership' do
    native = ActionDispatch::Integration::Session.new(Rails.application)
    native.cookies['cw_d_session_info'] = native_headers.to_json
    native.get '/portal/session'
    expect(native.response).to have_http_status(:ok)
    native.patch '/portal/session', params: { context_id: grant.id }, as: :json
    expect(native.response).to have_http_status(:ok)
    cookie = Array(native.response.headers['Set-Cookie']).find { |value| value.start_with?('_jrc_requester_portal=') }
    expect(cookie.present?).to be(true)
    expect(cookie.split(';').drop(1).map(&:strip)).to include('httponly')
    native.get '/portal/api/catalogo'
    expect(native.response).to have_http_status(:ok)
    expect(portal_user.account_users).to be_empty
  end

  it 'treats malformed native dashboard cookies as unauthenticated' do
    visitor = ActionDispatch::Integration::Session.new(Rails.application)
    ['[]', 'null', 'not-json'].each do |cookie|
      visitor.cookies['cw_d_session_info'] = cookie
      visitor.get '/portal/session'
      expect(visitor.response).to have_http_status(:unauthorized)
    end
  end

  it 'rejects blocked customers, disabled grants and Accounts without explicit opt-in' do
    sd_contact.update!(blocked: true)
    get '/portal/api/catalogo'
    expect(response).to have_http_status(:forbidden)
    sd_contact.update!(blocked: false)
    sd_account.update!(internal_attributes: sd_account.internal_attributes.except('requester_portal_enabled'))
    get '/portal/api/catalogo'
    expect(response).to have_http_status(:forbidden)
    expect(sd_account.reload.internal_attributes['requester_portal_enabled']).to be_nil
  end

  it 'rejects a context switch to a grant owned by another User' do
    other_user = create(:user)
    other_grant = JrcServiceDesk::PortalGrant.create!(account: sd_account, user: other_user, company: company, contact: sd_contact,
                                                    inbox: widget.inbox, contact_inbox: identity, granted_by: sd_user, active: true)
    patch '/portal/session', params: { context_id: other_grant.id, account_id: sd_account.id }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    patch '/portal/session', params: { context_id: other_grant.id }, as: :json
    expect(response).to have_http_status(:forbidden)
    get '/portal/session'
    expect(response.parsed_body.dig('context', 'id')).to eq(grant.id.to_s)
  end

  it 'switches only to another authorized organization and clears the prior customer scope' do
    company_b = JrcCustomers::Company.create!(account: sd_account, name: 'Authorized company B')
    contact_b = create(:contact, account: sd_account, company_id: company_b.id)
    identity_b = create(:contact_inbox, contact: contact_b, inbox: widget.inbox, hmac_verified: true)
    grant_b = JrcServiceDesk::PortalGrant.create!(account: sd_account, user: portal_user, company: company_b, contact: contact_b,
                                                inbox: widget.inbox, contact_inbox: identity_b, granted_by: sd_user, active: true)
    patch '/portal/session', params: { context_id: grant_b.id }, as: :json
    expect(response).to have_http_status(:ok)
    get '/portal/session'
    expect(response.parsed_body.dig('context', 'organization')).to eq(company_b.name)
    expect(response.parsed_body.dig('context', 'contact', 'name')).to eq(contact_b.name)
  end

  it 'requires CSRF even when a valid native bearer identity is supplied to the cookie bridge' do
    allow_any_instance_of(RequesterPortal::SessionsController).to receive(:protect_against_forgery?).and_return(true)
    post '/portal/session', params: {}, headers: native_headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'preserves valid/invalid native password authentication and denies a native user without a portal grant' do
    post '/auth/sign_in', params: { email: portal_user.email, password: 'wrong-password' }, as: :json
    expect(response).to have_http_status(:unauthorized)
    post '/auth/sign_in', params: { email: portal_user.email, password: 'Portal@Test123' }, as: :json
    expect(response).to have_http_status(:ok)
    headers = RequesterPortal::NativeSession::HEADERS.index_with { |key| response.headers[key] }
    post '/portal/session', params: {}, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    post '/portal/session', params: {}, headers: create(:user).create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'keeps native MFA verification mandatory before a portal session can be established' do
    skip 'Native encryption is required for the existing MFA implementation' unless Chatwoot.encryption_configured?
    portal_user.enable_two_factor!
    portal_user.update!(otp_required_for_login: true)
    post '/auth/sign_in', params: { email: portal_user.email, password: 'Portal@Test123' }, as: :json
    expect(response).to have_http_status(:partial_content)
    token = response.parsed_body['mfa_token']
    expect(response.headers['access-token']).to be_nil
    post '/auth/sign_in', params: { mfa_token: token, otp_code: portal_user.current_otp }, as: :json
    expect(response).to have_http_status(:ok)
    headers = RequesterPortal::NativeSession::HEADERS.index_with { |key| response.headers[key] }
    post '/portal/session', params: {}, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
  end
end

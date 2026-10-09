# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'R3 complete customer portal through the verified native widget', type: :request do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  include ActiveSupport::Testing::TimeHelpers

  let(:sd_contact) { create(:contact, account: sd_account, identifier: SecureRandom.uuid) }
  let(:widget) { create(:channel_widget, account: sd_account) }
  let(:identity) { create(:contact_inbox, contact: sd_contact, inbox: widget.inbox, hmac_verified: true) }
  let(:conversation) { create(:conversation, account: sd_account, contact: sd_contact, inbox: widget.inbox, contact_inbox: identity) }
  let(:service) do
    JrcServiceDesk::Service.create!(
      account: sd_account, unit: sd_unit, code: 'r3-portal', name: 'Customer support', active: true,
      default_priority: sd_priority, portal_inbox: widget.inbox, portal_execution_membership: sd_membership
    )
  end
  let(:ticket) { sd_ticket(service: service, title: 'Customer circuit failure') }
  let(:base) { '/api/v1/widget/service_desk' }
  let(:headers) do
    { 'X-Auth-Token' => Widget::TokenService.new(payload: { source_id: identity.source_id, inbox_id: widget.inbox.id }).generate_token,
      'X-Service-Desk-Identifier' => sd_contact.identifier,
      'X-Service-Desk-Identity-Token' => OpenSSL::HMAC.hexdigest('sha256', widget.hmac_token, sd_contact.identifier),
      'Idempotency-Key' => 'r3-portal-request' }
  end
  let(:creation) do
    { service_id: service.id, service_revision: JrcServiceDesk::ConfigurationResources.revision('services', service),
      title: 'Explicit customer request', description: 'Customer evidence', service_fields: {} }
  end
  let(:order) do
    JrcCrm::SalesOrder.create!(account: sd_account, owner: sd_user, contact: sd_contact, source_type: 'manual',
                               order_origin: 'direct_sale', status: 'completed')
  end
  let(:contract) do
    row = JrcCrm::Contract.create!(account: sd_account, owner: sd_user, contact: sd_contact, sales_order: order, status: 'draft')
    row.signed_document.attach(io: StringIO.new("%PDF-1.4\n1 0 obj <</Type /Catalog>> endobj\nstartxref\n0\n%%EOF"),
                               filename: 'portal-test-contract.pdf', content_type: 'application/pdf')
    row.update!(status: 'active', signature_status: 'signed', signature_mode: 'manual', signed_at: Time.current,
                signed_by_name: 'Test customer')
    row
  end

  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_crm', 'jrc_customer_master', 'jrc_relationship', 'help_center')
    sd_status
    service.update!(portal_enabled: true)
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
  end

  it 'uses only published articles and public locales from the portal bound to this exact inbox' do
    portal = create(:portal, account: sd_account,
                             config: { allowed_locales: %w[en pt_BR], default_locale: 'en', draft_locales: ['pt_BR'] })
    widget.inbox.update!(portal: portal)
    allowed = create(:article, account: sd_account, portal: portal, title: 'Circuit answer', description: 'Published evidence')
    create(:article, account: sd_account, portal: portal, title: 'Private draft', status: :draft)
    create(:article, account: sd_account, portal: portal, title: 'Draft locale', locale: 'pt_BR')
    other_portal = create(:portal, account: sd_account)
    create(:article, account: sd_account, portal: other_portal, title: 'Other inbox answer')
    create(:article, title: 'Other account answer')
    get "#{base}/knowledge", params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('articles').pluck('id')).to eq([allowed.id.to_s])
    expect(response.parsed_body.fetch('articles').first.fetch('path')).to eq("/hc/#{portal.slug}/articles/#{allowed.slug}")
    expect(response.body).not_to include('Private draft', 'Draft locale', 'Other inbox answer', 'Other account answer', 'author_id', 'content')
  end

  it 'searches existing native published article content without publishing drafts or exposing full bodies' do
    portal = create(:portal, account: sd_account)
    widget.inbox.update!(portal: portal)
    answer = create(:article, account: sd_account, portal: portal, title: 'Published guide', content: 'Circuit restoration steps')
    create(:article, account: sd_account, portal: portal, title: 'Unrelated guide', content: 'Printer toner')
    create(:article, account: sd_account, portal: portal, title: 'Private guide', content: 'Circuit diagnostics', status: :draft)
    get "#{base}/knowledge", params: { website_token: widget.website_token, q: 'Circuit' }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('articles').pluck('id')).to eq([answer.id.to_s])
    expect(response.body).not_to include('Circuit restoration steps', 'Private guide')
  end

  it 'offers no knowledge from an archived portal or disabled native Help Center and rejects oversized searches' do
    portal = create(:portal, account: sd_account, archived: true)
    widget.inbox.update!(portal: portal)
    create(:article, account: sd_account, portal: portal)
    get "#{base}/knowledge", params: { website_token: widget.website_token }, headers: headers
    expect(response.parsed_body.fetch('articles')).to be_empty
    portal.update!(archived: false)
    sd_account.disable_features!('help_center')
    get "#{base}/knowledge", params: { website_token: widget.website_token }, headers: headers
    expect(response.parsed_body.fetch('articles')).to be_empty
    get "#{base}/knowledge", params: { website_token: widget.website_token, q: 'a' * 201 }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'searches only customer tickets linked through this inbox and denies forged or revoked identity proofs' do
    unrelated = sd_ticket(service: service, title: 'Unrelated customer subject')
    create(:jrc_sd_conversation_link, ticket: unrelated, conversation: conversation)
    hidden = sd_ticket(service: service, requester: create(:contact, account: sd_account), title: 'Other customer circuit')
    get "#{base}/tickets", params: { website_token: widget.website_token, q: 'circuit' }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('tickets').pluck('id')).to eq([ticket.id.to_s])
    get "#{base}/tickets/#{hidden.id}", params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:not_found)
    forged = headers.merge('X-Service-Desk-Identity-Token' => 'a' * 64)
    get "#{base}/knowledge", params: { website_token: widget.website_token }, headers: forged
    expect(response).not_to have_http_status(:ok)
    identity.update!(hmac_verified: false)
    get "#{base}/tickets", params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'retains active older tickets while applying the explicit history retention window to completed tickets' do
    service.update!(portal_history_days: 1)
    ticket.update!(updated_at: 10.days.ago)
    completed = sd_ticket(service: service, title: 'Old completed history')
    resolved = create(:jrc_sd_status, unit: sd_unit, initial: false, phase: 'resolved')
    completed.update!(status: resolved)
    completed.update!(updated_at: 10.days.ago)
    create(:jrc_sd_conversation_link, ticket: completed, conversation: conversation)
    get "#{base}/tickets", params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('tickets').pluck('id')).to eq([ticket.id.to_s])
    get "#{base}/tickets/#{completed.id}", params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:not_found)
    service.update!(portal_history_days: nil)
    get "#{base}/tickets/#{completed.id}", params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:ok)
  end

  it 'does not reuse a verified identity from another inbox to expose the same customer ticket' do
    other_widget = create(:channel_widget, account: sd_account)
    other_identity = create(:contact_inbox, contact: sd_contact, inbox: other_widget.inbox, hmac_verified: true)
    other_conversation = create(:conversation, account: sd_account, contact: sd_contact, inbox: other_widget.inbox, contact_inbox: other_identity)
    other_ticket = sd_ticket(service: service, title: 'Other inbox customer request')
    create(:jrc_sd_conversation_link, ticket: other_ticket, conversation: other_conversation)
    get "#{base}/tickets", params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('tickets').pluck('id')).to eq([ticket.id.to_s])
    get "#{base}/tickets/#{other_ticket.id}", params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'rechecks explicit access expiry before catalogue, history and customer writes without deleting any ticket' do
    service.update!(portal_access_until: 1.second.ago)
    get "#{base}/services", params: { website_token: widget.website_token }, headers: headers
    expect(response.parsed_body.fetch('services')).to be_empty
    get "#{base}/tickets/#{ticket.id}", params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:not_found)
    expect do
      post "#{base}/tickets", params: { website_token: widget.website_token, ticket: creation }, headers: headers, as: :json
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response).to have_http_status(:not_found)
    expect(JrcServiceDesk::Ticket.exists?(ticket.id)).to be(true)
  end

  it 'publishes merged service/type/category fields and hides a contradictory or inactive catalogue' do
    type = JrcServiceDesk::TicketType.create!(account: sd_account, unit: sd_unit, name: 'Request', code: 'portal-request', active: true,
                                              form_fields: [{ key: 'impact', label: 'Impact', type: 'text', required: true }])
    category = create(:jrc_sd_category, unit: sd_unit, form_fields: [{ key: 'circuit', label: 'Circuit', type: 'text', required: true }])
    service.update!(default_ticket_type: type, default_category: category,
                    form_fields: [{ key: 'symptom', label: 'Symptom', type: 'text', required: true }])
    get "#{base}/services", params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('services').first.fetch('form_fields').pluck('key')).to eq(%w[symptom impact circuit])
    category.update!(form_fields: type.form_fields)
    get "#{base}/services", params: { website_token: widget.website_token }, headers: headers
    expect(response.parsed_body.fetch('services')).to be_empty
    category.update!(form_fields: [], active: false)
    get "#{base}/services", params: { website_token: widget.website_token }, headers: headers
    expect(response.parsed_body.fetch('services')).to be_empty
  end

  it 'publishes the explicit eligible native contracts and marks contract selection as required' do
    eligible = restrict_contracts
    get "#{base}/services", params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:ok)
    row = response.parsed_body.fetch('services').first
    expect(row.fetch('contract_required')).to be(true)
    expect(row.fetch('contracts').pluck('id')).to match_array(eligible.map { |record| record.id.to_s })
  end

  it 'rejects a required contract omission without inferring the first eligible native contract' do
    restrict_contracts
    expect do
      post "#{base}/tickets", params: { website_token: widget.website_token, ticket: creation }, headers: headers, as: :json
    end.not_to change(JrcServiceDesk::Ticket, :count)
    # The native process-with-exception wrapper maps in-action Pundit rejection to 401.
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq('error' => 'You are not authorized to do this action')
  end

  it 'creates the ticket with the explicitly chosen second contract and independently reads the same native references' do
    chosen = restrict_contracts.last
    post "#{base}/tickets", params: { website_token: widget.website_token, ticket: creation.merge(contract_id: chosen.id) },
                            headers: headers, as: :json
    expect(response).to have_http_status(:created)
    created = JrcServiceDesk::Ticket.find(response.parsed_body.dig('ticket', 'id'))
    expect(created.contract_id).to eq(chosen.id)
    get "#{base}/tickets/#{created.id}", params: { website_token: widget.website_token }, headers: headers
    expect(response.parsed_body.dig('ticket', 'contract_id')).to eq(chosen.id.to_s)
    expect(response.parsed_body.dig('ticket', 'service_id')).to eq(service.id.to_s)
  end

  it 'rechecks native executor capabilities when publishing catalogue data after a role revocation' do
    get "#{base}/services", params: { website_token: widget.website_token }, headers: headers
    expect(response.parsed_body.fetch('services').pluck('id')).to eq([service.id.to_s])
    role = create(:custom_role, account: sd_account, permissions: ['contact_manage'])
    sd_account_user.update!(custom_role: role)
    get "#{base}/services", params: { website_token: widget.website_token }, headers: headers
    expect(response.parsed_body.fetch('services')).to be_empty
    expect do
      post "#{base}/tickets", params: { website_token: widget.website_token, ticket: creation }, headers: headers, as: :json
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response).to have_http_status(:not_found)
  end

  it 'requires the explicitly linked conversation for a customer reply even when several conversations are authorized' do
    chosen = create(:conversation, account: sd_account, contact: sd_contact, inbox: widget.inbox, contact_inbox: identity)
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: chosen)
    unlinked = create(:conversation, account: sd_account, contact: sd_contact, inbox: widget.inbox, contact_inbox: identity)
    get "#{base}/tickets/#{ticket.id}", params: { website_token: widget.website_token }, headers: headers
    expect(response.parsed_body.fetch('conversations')).to contain_exactly(conversation.id.to_s, chosen.id.to_s)
    expect do
      post "#{base}/tickets/#{ticket.id}/replies",
           params: { website_token: widget.website_token, body: 'Explicit reply', conversation_id: unlinked.id }, headers: headers, as: :json
    end.not_to change(Message, :count)
    expect(response).to have_http_status(:not_found)
    post "#{base}/tickets/#{ticket.id}/replies",
         params: { website_token: widget.website_token, body: 'Explicit reply', conversation_id: chosen.id }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    message = Message.find(response.parsed_body.fetch('message_id'))
    expect(message.conversation_id).to eq(chosen.id)
    expect(message.sender).to eq(sd_contact)
    expect(message).to be_incoming
  end

  it 'projects persisted SLA clocks without a write or inferred completion and hides all internal note evidence' do
    lc_publish(definition: lc_definition(tracked: true), service: service)
    lc_snapshot(ticket)
    lc_execute(ticket, 'work_status')
    create(:jrc_sd_note, ticket: ticket, body: 'Internal diagnosis')
    before_clocks = ticket.sla_cycles.last.sla_clocks.order(:id).map(&:attributes)
    get "#{base}/tickets/#{ticket.id}", params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('sla').pluck('kind')).to contain_exactly('first_response', 'resolution')
    expect(response.parsed_body.fetch('sla').all? { |clock| clock['observed_at'].present? && clock['due_at'].present? }).to be(true)
    expect(ticket.sla_cycles.last.sla_clocks.order(:id).map(&:attributes)).to eq(before_clocks)
    expect(response.body).not_to include('Internal diagnosis', 'calendar_conditions', 'actor_membership', 'execution_membership')
  end

  it 'shows public delivery history as recorded and never exposes internal or private messages' do
    public_note = create(:jrc_sd_note, ticket: ticket, visibility: 'customer', body: 'Public update')
    internal_note = create(:jrc_sd_note, ticket: ticket, visibility: 'internal', body: 'Internal notification')
    public_message = create(:message, account: sd_account, conversation: conversation, inbox: widget.inbox,
                                      sender: sd_user, message_type: :outgoing, private: false, content: 'Recorded public delivery')
    private_message = create(:message, account: sd_account, conversation: conversation, inbox: widget.inbox,
                                       sender: sd_user, message_type: :outgoing, private: true, content: 'Private message')
    public_delivery = JrcServiceDesk::NotificationDelivery.create!(
      account: sd_account, unit: sd_unit, ticket: ticket,
      ticket_note: public_note, execution_membership: sd_membership, conversation: conversation, message: public_message,
      channel: 'email', state: 'sent', sent_at: Time.current
    )
    JrcServiceDesk::NotificationDelivery.create!(
      account: sd_account, unit: sd_unit, ticket: ticket,
      ticket_note: internal_note, execution_membership: sd_membership, conversation: conversation, message: public_message,
      channel: 'email', state: 'sent'
    )
    JrcServiceDesk::NotificationDelivery.create!(
      account: sd_account, unit: sd_unit, ticket: ticket,
      ticket_note: public_note, execution_membership: sd_membership, conversation: conversation, message: private_message,
      channel: 'whatsapp', state: 'sent'
    )
    get "#{base}/tickets/#{ticket.id}", params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:ok)
    rows = response.parsed_body.fetch('notification_history')
    expect(rows.pluck('id')).to eq([public_delivery.id.to_s])
    expect(rows.first.values_at('state', 'delivered_at', 'body')).to eq(['sent', nil, 'Recorded public delivery'])
    expect(response.body).not_to include('Private message', 'Internal notification', 'source_snapshot', 'execution_membership')
  end

  it 'reuses the shared survey engine and signed public route without dispatching a customer message' do
    decision = prepare_portal_survey
    expect(decision.state).to eq('scheduled')
    expect { JrcRelationship::SurveyDispatchJob.perform_now(decision.survey_id) }.not_to change(Message, :count)
    get "#{base}/tickets/#{ticket.id}", params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:ok)
    row = response.parsed_body.fetch('surveys').sole
    expect(row.values_at('id', 'kind')).to eq([decision.survey_id.to_s, 'csat'])
    expect(row.fetch('path')).to start_with('/jrc/relacionamento/pesquisas/')
    get row.fetch('path')
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('How was this support?')
  end

  it 'removes an expired shared survey from the authenticated customer readback' do
    decision = prepare_portal_survey
    JrcRelationship::SurveyDispatchJob.perform_now(decision.survey_id)
    get "#{base}/tickets/#{ticket.id}", params: { website_token: widget.website_token }, headers: headers
    expect(response.parsed_body.fetch('surveys').pluck('id')).to eq([decision.survey_id.to_s])
    decision.survey.reload.update!(expires_at: 1.second.ago)
    get "#{base}/tickets/#{ticket.id}", params: { website_token: widget.website_token }, headers: headers
    expect(response.parsed_body.fetch('surveys')).to be_empty
  end

  def restrict_contracts
    first = contract
    chosen = JrcCrm::Contract.create!(account: sd_account, owner: sd_user, contact: sd_contact, sales_order: order, status: 'draft')
    chosen.signed_document.attach(io: StringIO.new('%PDF test second contract'), filename: 'second.pdf', content_type: 'application/pdf')
    chosen.update!(status: 'active', signature_status: 'signed', signed_at: Time.current, signed_by_name: 'Test customer')
    service.update!(allowed_contract_ids: [first.id, chosen.id])
    [first, chosen]
  end

  def prepare_portal_survey
    resolved = create(:jrc_sd_status, unit: sd_unit, initial: false, phase: 'resolved')
    ticket.update!(status: resolved)
    sd_contact.update!(custom_attributes: { survey_consent: true })
    JrcRelationship::Assignment.create!(account: sd_account, contact: sd_contact, owner: sd_user, status: 'active')
    JrcRelationship::Configuration.create!(account: sd_account, rules: { survey_automation_enabled: true })
    definition = JrcRelationship::SurveyDefinition.create!(
      account: sd_account, name: 'Native ticket CSAT', code: 'portal-csat',
      kind: 'csat', status: 'active', questions: [{ key: 'rating', text: 'How was this support?', type: 'scale', min: 1, max: 5, required: true }],
      settings: { recovery_enabled: false }
    )
    JrcRelationship::SurveyRule.create!(
      account: sd_account, name: 'Ticket closure', definition: definition,
      execution_member: sd_account_user, active: true, matchers: { source_type: 'JrcServiceDesk::Ticket' }, settings: { channel: 'public_link' }
    )
    JrcRelationship::SurveyEngine.evaluate_closure(source: ticket, cycle_key: 'r3-native-closure')
  end
end

require 'rails_helper'

RSpec.describe 'HelpDesk native group preview and approvals', type: :request do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures

  let(:selected_group) { 'A1' }
  let(:selected_rule) { selected_group == 'C1' ? 'R01' : 'R16' }
  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'Synthetic group customer') }
  let(:ticket) { sd_ticket(company_id: company.id) }
  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_nico/helpdesk" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:input) { { 'summary' => 'Reviewed local request; external system action requires the responsible human.' } }
  let(:definition) do
    value = JrcNico::Helpdesk::Definition.defaults.merge('unit_ids' => [sd_unit.id], 'company_ids' => [company.id],
                                                         'operator_ids' => [sd_account_user.id])
    value['rules'][selected_rule]['enabled'] = true
    value['groups'][selected_group]['enabled'] = true
    value
  end
  let(:policy) do
    JrcNico::Helpdesk::PolicyVersion.create!(account: sd_account, author: sd_account_user, number: 1, state: 'published',
                                             enabled: true, published_at: Time.current, definition: definition, digest: JrcNico::Helpdesk::Definition.digest(definition))
  end
  def event
    @native_group_event ||= capture_group_event
  end

  def capture_group_event
    prepare_group_recurrence
    policy
    values = JrcNico::Helpdesk::Capture.new(sd_account_user).call(ticket: ticket,
                                                                  trigger: selected_rule == 'R16' ? 'created' : 'monitor', origin_key: "native-group:#{ticket.id}")
    expect(values.map(&:rule_key)).to eq([selected_rule])
    value = values.fetch(0)
    JrcNico::Helpdesk::EventJob.perform_now(value.id)
    expect(value.reload.state).to eq('prepared')
    value
  end

  def prepare_group_recurrence
    return unless selected_rule == 'R01'

    [ticket, sd_ticket(company_id: company.id)].each do |row|
      JrcNico::Helpdesk::TicketProfile.create!(account: sd_account, unit: sd_unit, ticket: row, company: company,
                                               case_kind: 'defect', defect_key: 'voice.trunk')
    end
  end

  before do
    sd_account.update!(custom_attributes: { 'nico_enabled' => true })
    sd_account.enable_features!('jrc_customer_master')
    sd_as_admin!
  end

  def preview(extra = {})
    post "#{base}/group_preview", params: { event_id: event.id, group_key: selected_group, input: input.merge(extra) },
                                  headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    response.parsed_body
  end

  def prepare(value, action, group_input = input)
    post "#{base}/group_prepare", params: { event_id: event.id, group_key: selected_group, input: group_input,
                                            tool: action.fetch('tool'), arguments: action.fetch('arguments'), preview_digest: value.fetch('preview_digest') }, headers: headers, as: :json
  end

  def verify_group_preview(value, key)
    expect(value).to include('group_key' => key, 'enabled' => true, 'preview' => true, 'persisted' => false, 'automatic_execution' => false)
    expect(value.dig('source', 'ticket_id')).to eq(ticket.id)
  end

  def verify_group_receipt(record, key)
    note = JrcServiceDesk::TicketNote.find(record.command.reload.result.dig('record', 'id'))
    expect(note).to have_attributes(ticket_id: ticket.id, unit_id: sd_unit.id, account_id: sd_account.id,
                                    visibility: 'internal', author_membership_id: sd_membership.id)
    expect(note.body).to include("NICO HelpDesk #{key}", "source event #{event.id}", input.fetch('summary'))
    expect(note.notification_channels).to eq([])
    note
  end

  def replay_and_revoke_group(approval, note)
    expect do
      post "#{base}/approvals/#{approval.fetch('id')}/approve", params: { payload_digest: approval.fetch('payload_digest') },
                                                                headers: headers, as: :json
    end.not_to change(JrcServiceDesk::TicketNote, :count)
    expect(response).to have_http_status(:ok)
    get "#{base}/approvals", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('approvals').pluck('id')).to include(approval.fetch('id'))
    sd_membership.update!(active: false)
    get "#{base}/approvals", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('approvals')).to be_empty
    expect(note.reload).to be_persisted
  end

  def verify_pending_group_hidden(approval)
    get "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/tickets/#{ticket.id}", headers: headers
    expect(response).to have_http_status(:ok)
    get "#{base}/approvals", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('approvals')).to be_empty
    expect(approval.reload.state).to eq('pending')
  end

  JrcNico::Helpdesk::Definition::GROUP_KEYS.each do |key|
    context "with local group #{key}" do
      let(:selected_group) { key }

      it 'captures the real source and persists the approved internal dossier once without external execution' do
        value = nil
        expect { value = preview }.not_to change(JrcServiceDesk::TicketNote, :count)
        verify_group_preview(value, key)
        action = value.fetch('actions').find { |candidate| candidate['tool'] == 'add_service_ticket_note' }
        expect(action.fetch('can_prepare')).to be(true)
        prepare(value, action)
        expect(response).to have_http_status(:created)
        approval = response.parsed_body
        expect(approval.dig('scope', 'group', 'group_key')).to eq(key)
        expect do
          post "#{base}/approvals/#{approval.fetch('id')}/approve", params: { payload_digest: approval.fetch('payload_digest') },
                                                                    headers: headers, as: :json
        end.to change(JrcServiceDesk::TicketNote, :count).by(1)
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.fetch('state')).to eq('succeeded')
        record = JrcNico::Helpdesk::Approval.find(approval.fetch('id'))
        note = verify_group_receipt(record, key)
        replay_and_revoke_group(approval, note)
      end
    end
  end

  it 'keeps old policies with no groups and all new defaults OFF while allowing a read-only diagnostic' do
    definition.delete('groups')
    value = preview
    expect(value).to include('enabled' => false, 'executable' => false)
    prepare(value, value.fetch('actions').first)
    expect(response).to have_http_status(:unauthorized)
    expect(JrcNico::Helpdesk::Approval.where(account: sd_account)).to be_empty
    expect(JrcNico::Helpdesk::Definition.defaults['groups'].values.pluck('enabled')).to eq([false] * 11)
  end

  it 'retains requester sources and hides the pending dossier when only customer permission is revoked' do
    value = preview
    expect(value.fetch('resources')).to include(['Contact', sd_contact.id], ['JrcNico::ServiceTicketCustomer', ticket.id])
    prepare(value, value.fetch('actions').first)
    expect(response).to have_http_status(:created)
    approval = JrcNico::Helpdesk::Approval.find(response.parsed_body.fetch('id'))
    permissions = %w[module_view tickets_view notes_view notes_add history_view sla_view]
    role = create(:custom_role, account: sd_account, permissions: permissions.map { |key| "jrc_service_desk_#{key}" })
    sd_account_user.update!(role: :agent, custom_role: role)
    verify_pending_group_hidden(approval)
    expect(JrcServiceDesk::TicketNote.where(ticket: ticket)).to be_empty
  end

  context 'with real closed history in group E' do
    let(:selected_group) { 'E' }

    it 'retains exact history sources and hides the saved solution when only note visibility is revoked' do
      lc_publish
      closed = sd_ticket(company_id: company.id)
      lc_execute(closed, 'resolve', solution: 'Synthetic native resolution')
      close = lc_execute(closed, 'close', solution: 'Protected native closure evidence')
      value = preview
      expect(value.fetch('evidence')).to include(hash_including('kind' => 'native_closed_solution', 'id' => close.id,
                                                                'solution' => 'Protected native closure evidence'))
      expect(value.fetch('resources')).to include(['JrcServiceDesk::Ticket', closed.id],
                                                  ['JrcServiceDesk::LifecycleTransition', close.id], ['JrcNico::ServiceTicketNotes', closed.id])
      prepare(value, value.fetch('actions').first)
      expect(response).to have_http_status(:created)
      approval = JrcNico::Helpdesk::Approval.find(response.parsed_body.fetch('id'))
      permissions = %w[module_view tickets_view history_view sla_view]
      role = create(:custom_role, account: sd_account, permissions: permissions.map { |key| "jrc_service_desk_#{key}" })
      sd_account_user.update!(role: :agent, custom_role: role)
      context = JrcNico::Helpdesk::Context.new(sd_account_user)
      expect(JrcNico::DomainAccess.authorize_resource!(context.access, close.class.name, close.id)).to eq(close)
      verify_pending_group_hidden(approval)
      expect(close.reload.payload['solution']).to eq('Protected native closure evidence')
    end
  end

  it 'cannot borrow a legal event as an arbitrary request group or invent dispatch fields' do
    legal = JrcNico::Helpdesk::Event.create!(account: sd_account, ticket: ticket, actor: sd_account_user, policy_version: policy,
                                             rule_key: 'R11', evidence: {}, correlation_key: 'synthetic-legal-boundary', detected_at: Time.current)
    post "#{base}/group_preview", params: { event_id: legal.id, group_key: 'A1', input: input }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    post "#{base}/group_preview", params: { event_id: event.id, group_key: 'A1', input: input.merge('endpoint' => '/arbitrary') },
                                  headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcNico::Helpdesk::Approval.where(account: sd_account)).to be_empty
  end

  it 'cannot borrow an older R16 request event after the current native profile becomes legal' do
    value = event
    JrcNico::Helpdesk::TicketProfile.create!(account: sd_account, unit: sd_unit, ticket: ticket, company: company,
                                             case_kind: 'legal', legal_risk: true)
    post "#{base}/group_preview", params: { event_id: value.id, group_key: 'A1', input: input }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcNico::Helpdesk::Approval.where(account: sd_account)).to be_empty
    definition['groups']['D2']['enabled'] = true
    # A separate explicit immutable policy is required; the old published definition is not edited.
    second_policy = JrcNico::Helpdesk::PolicyVersion.create!(account: sd_account, author: sd_account_user, number: 2,
                                                             state: 'published', enabled: true, published_at: Time.current, definition: definition,
                                                             digest: JrcNico::Helpdesk::Definition.digest(definition))
    second = JrcNico::Helpdesk::Event.create!(account: sd_account, ticket: ticket, actor: sd_account_user,
                                              policy_version: second_policy, rule_key: 'R16', evidence: value.evidence,
                                              correlation_key: 'synthetic-reviewed-legal-d2', detected_at: Time.current)
    post "#{base}/group_preview", params: { event_id: second.id, group_key: 'D2', input: input }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('group_key' => 'D2', 'enabled' => true)
  end

  it 'rejects overflowing, untyped and non-finite native identifiers and catalogue answers before preparation' do
    [input.merge('binding_id' => 9_223_372_036_854_775_808),
     input.merge('classification' => { 'ticket_type_id' => '1' }),
     input.merge('classification' => { 'service_fields' => ['unsupported answers'] }),
     input.merge('handoff' => { 'queue_id' => -1 })].each do |invalid_input|
      post "#{base}/group_preview", params: { event_id: event.id, group_key: selected_group, input: invalid_input },
                                    headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'HELPDESK_INVALID_REQUEST')
    end
    expect(JrcNico::Helpdesk::Approval.where(account: sd_account)).to be_empty
  end

  it 'binds native evidence, exact tool arguments and expiry and rejects mutation before approval' do
    value = preview
    action = value.fetch('actions').first
    prepare(value, action.merge('arguments' => action.fetch('arguments').merge('body' => 'Unreviewed overwrite')))
    expect(response).to have_http_status(:unauthorized)
    prepare(value, action)
    expect(response).to have_http_status(:created)
    approval = JrcNico::Helpdesk::Approval.find(response.parsed_body.fetch('id'))
    ticket.update!(title: 'Source changed after review')
    expect { JrcNico::Helpdesk::Approvals.new(sd_account_user).approve(id: approval.id, payload_digest: approval.payload_digest) }
      .to raise_error(ArgumentError, /evidence changed/)
    expect(approval.reload.state).to eq('pending')
    expect(JrcServiceDesk::TicketNote.where(ticket: ticket)).to be_empty
  end

  context 'with native D1 classification' do
    let(:selected_group) { 'D1' }
    let(:type) do
      JrcServiceDesk::TicketType.create!(account: sd_account, unit: sd_unit, code: 'synthetic-request', name: 'Reviewed request', active: true,
                                         form_fields: [{ 'key' => 'device', 'label' => 'Device', 'type' => 'text', 'required' => true }])
    end

    def verify_classification_receipt(type)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('state')).to eq('succeeded')
      expect(ticket.reload).to have_attributes(ticket_type_id: type.id, service_fields: { 'device' => 'Explicit test device' })
      expect(ticket.catalogue_snapshot.dig('classification', 'ticket_types', 'id')).to eq(type.id)
      update = ticket.ticket_events.find_by!(event_type: 'ticket_updated')
      expect(update.data.fetch('origin').fetch('kind')).to eq('operator_assisted_nico')
      get "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/tickets/#{ticket.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Explicit test device')
    end

    it 'asks for the required catalogue answers then approves, persists and reloads actual classification' do
      incomplete = preview('classification' => { 'ticket_type_id' => type.id })
      expect(incomplete.fetch('required_fields')).to eq(['device'])
      blocked = incomplete.fetch('actions').find { |row| row['tool'] == 'update_service_ticket' }
      expect(blocked).to include('can_prepare' => false, 'blocked_reason' => 'required_catalogue_answers_missing')
      classification = { 'ticket_type_id' => type.id, 'service_fields' => { 'device' => 'Explicit test device' } }
      value = preview('classification' => classification)
      action = value.fetch('actions').find { |row| row['tool'] == 'update_service_ticket' }
      expect(action.fetch('can_prepare')).to be(true)
      prepare(value, action, input.merge('classification' => classification))
      expect(response).to have_http_status(:created)
      approval = response.parsed_body
      post "#{base}/approvals/#{approval.fetch('id')}/approve", params: { payload_digest: approval.fetch('payload_digest') },
                                                                headers: headers, as: :json
      verify_classification_receipt(type)
    end

    it 'rejects a classification reference from another Unit before preparing an approval' do
      foreign = JrcServiceDesk::TicketType.create!(account: sd_account, unit: sd_other_unit, code: 'synthetic-other', name: 'Foreign unit',
                                                   active: true)
      post "#{base}/group_preview", params: { event_id: event.id, group_key: 'D1',
                                              input: input.merge('classification' => { 'ticket_type_id' => foreign.id }) }, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq('error' => 'Resource could not be found')
      expect(ticket.reload.ticket_type_id).to be_nil
      expect(JrcNico::Helpdesk::Approval.where(account: sd_account)).to be_empty
    end
  end

  context 'with B2 attempts and approved knowledge' do
    let(:selected_group) { 'B2' }

    def verify_attempt_execution
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('state')).to eq('succeeded')
    end

    it 'records only approved native attempts and requires human handoff after the second one' do
      2.times do
        value = preview
        action = value.fetch('actions').find { |row| row['tool'] == 'add_service_ticket_note' }
        prepare(value, action)
        expect(response).to have_http_status(:created)
        approval = response.parsed_body
        post "#{base}/approvals/#{approval.fetch('id')}/approve", params: { payload_digest: approval.fetch('payload_digest') },
                                                                  headers: headers, as: :json
        verify_attempt_execution
      end
      value = preview
      expect(value.fetch('attempts')).to include('recorded' => 2, 'handoff_required' => true)
      action = value.fetch('actions').find { |row| row['tool'] == 'add_service_ticket_note' }
      expect(action).to include('can_prepare' => false, 'blocked_reason' => 'two_attempts_require_native_handoff')
      prepare(value, action)
      expect(response).to have_http_status(:unauthorized)
      expect(ticket.ticket_notes.count).to eq(2)
    end

    it 'binds approved KB digest and hides the persisted preview after that exact source loses approval' do
      document = JrcNico::KnowledgeDocument.create!(account: sd_account, author: sd_user, approved_by: sd_user,
                                                    approved_at: Time.current, title: 'Guia de ramal', body: 'Instruções locais de ramal revisadas.')
      group_input = input.merge('query' => 'ramal')
      value = preview('query' => 'ramal')
      expect(value.fetch('evidence').pluck('kind')).to include('approved_native_knowledge')
      prepare(value, value.fetch('actions').first, group_input)
      expect(response).to have_http_status(:created)
      approval_id = response.parsed_body.fetch('id')
      document.update!(body: 'Modified guide loses its approval')
      get "#{base}/approvals", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('approvals').pluck('id')).not_to include(approval_id)
      value = JrcNico::Helpdesk::Approval.find(approval_id)
      expect { JrcNico::Helpdesk::Approvals.new(sd_account_user).approve(id: value.id, payload_digest: value.payload_digest) }
        .to raise_error(ArgumentError, /evidence changed/)
      expect(ticket.ticket_notes).to be_empty
    end

    it 'blocks a second native attempt while an earlier outcome is unknown instead of blindly replaying it' do
      value = preview
      prepare(value, value.fetch('actions').first)
      expect(response).to have_http_status(:created)
      approval = JrcNico::Helpdesk::Approval.find(response.parsed_body.fetch('id'))
      approval.command.update!(status: 'unknown')
      approval.update!(state: 'unknown', approved_at: Time.current)
      changed_input = input.merge('summary' => 'Another explicit operator request cannot bypass reconciliation')
      next_preview = preview('summary' => changed_input.fetch('summary'))
      prepare(next_preview, next_preview.fetch('actions').first, changed_input)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JrcNico::Helpdesk::Approval.where(account: sd_account).count).to eq(1)
      expect(ticket.ticket_notes).to be_empty
    end
  end

  context 'with the native C2 Broker connection' do
    let(:selected_group) { 'C2' }
    let(:inbox) { create(:channel_api, account: sd_account).inbox }
    let(:conversation) { create(:conversation, account: sd_account, inbox: inbox, contact: sd_contact) }
    let(:binding) do
      JrcBrokerInboxBinding.create!(account: sd_account, inbox: inbox, integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid)
    end
    let(:broker_input) { { 'binding_id' => binding.id, 'conversation_id' => conversation.display_id } }
    def remote
      'https://broker.example.test/v1/integrations/chatwoot/control'
    end

    def organization_id
      @broker_organization_id ||= SecureRandom.uuid
    end

    def encrypted
      @broker_encrypted_key ||= JrcBroker::Configuration.credential_store.encrypt(account_id: sd_account.id, token: 'synthetic-control')
    end

    def health
      { integrationId: binding.integration_id, instanceId: binding.instance_id, inboxId: inbox.id,
        integrationStatus: 'READY', identityApproved: true, identityStatus: 'VERIFIED', allowedActions: %w[status pair] }
    end

    def verify_local_broker_preparation
      expect(a_request(:get, "#{remote}/connections/#{binding.integration_id}/status")).to have_been_made.once
      expect(a_request(:post, "#{remote}/connections/#{binding.integration_id}/pair")).not_to have_been_made
      expect(response.body).not_to include('synthetic-control', encrypted)
    end

    around do |example|
      with_modified_env(JRC_BROKER_ENABLED: 'true', JRC_BROKER_ALLOWED_ORIGINS: 'https://broker.example.test',
                        JRC_BROKER_CREDENTIAL_KEY: Base64.strict_encode64('k' * 32), FRONTEND_URL: 'https://chatwoot.example.test') { example.run }
    end

    before do
      sd_account.enable_features!('jrc_broker')
      JrcBrokerIntegration.create!(account: sd_account, broker_origin: 'https://broker.example.test', organization_id: organization_id,
                                   destination_revision: 1, encrypted_control_key: encrypted)
      create(:inbox_member, inbox: inbox, user: sd_user)
      JrcBrokerInboxGrant.create!(account: sd_account, inbox: inbox, binding: binding, user: sd_user, can_pair: true)
      JrcServiceDesk::LinkConversationService.new(user_context: sd_context).call(ticket_id: ticket.id, conversation_id: conversation.id)
      stub_request(:get, "#{remote}/context").to_return(status: 200, body: {
        organizationId: organization_id, accountId: sd_account.id, chatwootOrigin: 'https://chatwoot.example.test',
        destinationRevision: 1, capabilities: {}
      }.to_json)
      stub_request(:get, "#{remote}/connections/#{binding.integration_id}/status").to_return(status: 200, body: health.to_json)
    end

    it 'uses native Control status only on explicit read and prepares local approval without pairing I/O' do
      sd_account_user.update!(role: :agent)
      value = preview(broker_input.merge('check_broker_status' => true))
      expect(value.fetch('broker')).to include('binding_id' => binding.id, 'conversation_id' => conversation.display_id,
                                               'status' => 'READY', 'pair_allowed' => true, 'identity_approved' => true, 'route_name' => 'jrc_broker_connections')
      expect(a_request(:get, "#{remote}/connections/#{binding.integration_id}/status")).to have_been_made.once
      prepare(value, value.fetch('actions').first, input.merge(broker_input).merge('check_broker_status' => true))
      expect(response).to have_http_status(:unprocessable_entity)
      local = preview(broker_input)
      expect(local.dig('broker', 'status')).to eq('not_requested')
      prepare(local, local.fetch('actions').first, input.merge(broker_input))
      expect(response).to have_http_status(:created)
      verify_local_broker_preparation
    end

    it 'denies a foreign inbox binding and current inbox membership removal before any Broker request' do
      sd_account_user.update!(role: :agent)
      foreign_inbox = create(:channel_api, account: sd_foreign_account).inbox
      JrcBrokerIntegration.create!(account: sd_foreign_account, broker_origin: 'https://broker.example.test',
                                   organization_id: SecureRandom.uuid, destination_revision: 1,
                                   encrypted_control_key: JrcBroker::Configuration.credential_store.encrypt(
                                     account_id: sd_foreign_account.id, token: 'synthetic-foreign-control'
                                   ))
      foreign = JrcBrokerInboxBinding.create!(account: sd_foreign_account, inbox: foreign_inbox,
                                              integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid)
      post "#{base}/group_preview", params: { event_id: event.id, group_key: 'C2',
                                              input: input.merge(broker_input).merge('binding_id' => foreign.id) }, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq('error' => 'Resource could not be found')
      InboxMember.find_by!(inbox: inbox, user: sd_user).destroy!
      post "#{base}/group_preview", params: { event_id: event.id, group_key: 'C2',
                                              input: input.merge(broker_input).merge('check_broker_status' => true) }, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(a_request(:get, "#{remote}/context")).not_to have_been_made
      expect(JrcNico::Helpdesk::Approval.where(account: sd_account)).to be_empty
    end
  end
end

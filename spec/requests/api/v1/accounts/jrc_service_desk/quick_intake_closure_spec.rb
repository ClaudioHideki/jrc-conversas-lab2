require 'rails_helper'

RSpec.describe 'Quick Service Desk intake and authorized closure plans', type: :request do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'Synthetic served company') }
  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master')
    sd_contact.update!(company_id: company.id, name: 'Synthetic requester', email: 'requester@disposable-mail.invalid', phone_number: '+5511999900001')
  end

  it 'creates a minimal ticket, rereads its company and person and safely replays the same request' do
    values = { unit_id: sd_unit.id, ticket: sd_create_attributes.merge(company_id: company.id) }
    2.times do
      post "#{base}/tickets", params: values, as: :json, headers: headers.merge('Idempotency-Key' => 'quick-minimum')
      expect(response).to have_http_status(:created)
    end
    expect(JrcServiceDesk::Ticket.where(idempotency_key: 'quick-minimum').count).to eq(1)
    id = response.parsed_body.fetch('ticket_id')
    get "#{base}/tickets/#{id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('ticket', 'requester', 'id')).to eq(sd_contact.id.to_s)
    expect(JrcServiceDesk::Ticket.find(id).company_id).to eq(company.id)
    expect(JrcServiceDesk::Ticket.find(id).ticket_events.where(event_type: 'ticket_created').count).to eq(1)
  end

  it 'filters companies before server pagination and excludes imported organization contacts' do
    org = create(:contact, account: sd_account, company_id: company.id, additional_attributes: { entity_type: 'company' })
    other_company = JrcCustomers::Company.create!(account: sd_account, name: 'Other synthetic company')
    other = create(:contact, account: sd_account, company_id: other_company.id)
    foreign = create(:contact, account: sd_foreign_account)
    get "#{base}/requesters", headers: headers, params: { unit_id: sd_unit.id, company_id: company.id, per_page: 1 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('meta', 'total')).to eq(1)
    expect(response.parsed_body.fetch('items').map { |item| item['id'] }).to eq([sd_contact.id.to_s])
    expect(response.body).not_to include(org.name, other.name, foreign.name)
  end

  ['Synthetic requester', 'requester@disposable-mail.invalid', '(11) 99990-0001'].each do |term|
    it "searches eligible requesters by #{term.include?('@') ? 'email' : term.start_with?('(') ? 'formatted phone' : 'name'}" do
      get "#{base}/requesters", headers: headers, params: { unit_id: sd_unit.id, company_id: company.id, q: term }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('items').map { |item| item['id'] }).to eq([sd_contact.id.to_s])
    end
  end

  it 'returns an actionable 422 for a requester linked to another served company without writing a ticket' do
    other_company = JrcCustomers::Company.create!(account: sd_account, name: 'Mismatch synthetic company')
    expect do
      post "#{base}/tickets", params: { unit_id: sd_unit.id, ticket: sd_create_attributes.merge(company_id: other_company.id) },
        as: :json, headers: headers.merge('Idempotency-Key' => 'wrong-company')
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('code' => 'requester_company_mismatch', 'fields' => ['requester_id'])
    expect(response.parsed_body['error']).to eq('Selecione um solicitante vinculado à empresa atendida.')
  end

  it 'rejects a company Contact as a person even with a forged creation payload' do
    sd_contact.update!(additional_attributes: { entity_type: 'company' })
    post "#{base}/tickets", params: { unit_id: sd_unit.id, ticket: sd_create_attributes.merge(company_id: company.id) },
      as: :json, headers: headers.merge('Idempotency-Key' => 'not-person')
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('requester_is_company')
    expect(JrcServiceDesk::Ticket.where(idempotency_key: 'not-person')).not_to exist
  end

  it 'denies a foreign company lookup and a foreign requester mutation without leaking identity' do
    foreign_company = JrcCustomers::Company.create!(account: sd_foreign_account, name: 'Foreign private company')
    foreign_contact = create(:contact, account: sd_foreign_account, company_id: foreign_company.id)
    get "#{base}/requesters", headers: headers, params: { unit_id: sd_unit.id, company_id: foreign_company.id }
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(foreign_company.name, foreign_contact.name)
    post "#{base}/tickets", params: { unit_id: sd_unit.id, ticket: sd_create_attributes.merge(requester_id: foreign_contact.id) },
      as: :json, headers: headers.merge('Idempotency-Key' => 'foreign-person')
    expect(response).to have_http_status(:not_found)
    expect(JrcServiceDesk::Ticket.where(idempotency_key: 'foreign-person')).not_to exist
  end

  it 'uses the official contact registry to create and reread a requester inside the same form context' do
    post "/api/v1/accounts/#{sd_account.id}/customers/contacts", as: :json, headers: headers,
      params: { contact: { name: 'New synthetic person', email: 'new.person@disposable-mail.invalid', company_id: company.id } }
    expect(response).to have_http_status(:created)
    id = response.parsed_body.dig('payload', 'id')
    expect(Contact.find(id).company_id).to eq(company.id)
    get "#{base}/requesters", headers: headers, params: { unit_id: sd_unit.id, company_id: company.id, q: 'new.person@disposable-mail.invalid' }
    expect(response.parsed_body.fetch('items').map { |item| item['id'] }).to eq([id.to_s])
  end

  it 'exposes both authorized official steps and persists resolution, final closure and two audit entries' do
    definition = lc_definition
    definition['transitions'].select { |r| %w[resolve close].include?(r['action']) }.each { |r| r['requirements']['solution'] = true }
    lc_publish(definition: definition)
    row = sd_ticket
    get "#{base}/tickets/#{row.id}/lifecycle", headers: headers
    plan = response.parsed_body.fetch('closure_options').sole
    expect(plan['steps'].map { |r| r['action'] }).to eq(%w[resolve close])
    plan['steps'].each_with_index do |step, index|
      get "#{base}/tickets/#{row.id}/lifecycle", headers: headers
      data = response.parsed_body
      command = { rule_key: step['key'], solution: 'Synthetic single resolution', expected_lock_version: data['lock_version'], expected_policy_version_id: data.dig('policy', 'id') }
      2.times do
        post "#{base}/tickets/#{row.id}/lifecycle", headers: headers.merge('Idempotency-Key' => "quick-close:#{index}"), params: command, as: :json
        expect(response).to have_http_status(:ok)
      end
    end
    expect(row.reload.status.phase).to eq('closed')
    expect(row.lifecycle_transitions.order(:id).pluck(:action)).to eq(%w[resolve close])
    expect(row.lifecycle_transitions.pluck(:payload).all? { |p| p['solution'] == 'Synthetic single resolution' }).to be(true)
    expect(row.lifecycle_transitions.pluck(:actor_membership_id)).to eq([sd_membership.id, sd_membership.id])
    expect(row.ticket_events.where(event_type: 'lifecycle_transitioned').count).to eq(2)
  end

  it 'does not present resolution alone as a complete closure' do
    definition = lc_definition
    definition['transitions'].reject! { |r| r['action'] == 'close' }
    lc_publish(definition: definition)
    row = sd_ticket
    get "#{base}/tickets/#{row.id}/lifecycle", headers: headers
    expect(response.parsed_body.fetch('options').map { |r| r['action'] }).to include('resolve')
    expect(response.parsed_body.fetch('closure_options')).to be_empty
  end

  it 'keeps contractual diagnosis, evidence and custom requirements mandatory in both the plan and official command' do
    definition = lc_definition
    definition['transitions'].find { |r| r['action'] == 'close' }['requirements'].merge!('note' => true, 'evidence' => true,
      'fields' => { 'accepted' => { 'label' => 'Contract acceptance', 'type' => 'boolean', 'required' => true, 'equals' => true } })
    lc_publish(definition: definition)
    row = sd_ticket
    get "#{base}/tickets/#{row.id}/lifecycle", headers: headers
    expect(response.parsed_body.dig('closure_options', 0, 'steps', 1, 'requirements', 'note')).to be(true)
    lc_execute(row, 'resolve', solution: 'Synthetic resolution')
    get "#{base}/tickets/#{row.id}/lifecycle", headers: headers
    data = response.parsed_body
    post "#{base}/tickets/#{row.id}/lifecycle", headers: headers.merge('Idempotency-Key' => 'missing-contract'), as: :json,
      params: { rule_key: 'close', solution: 'Only resolution', expected_lock_version: data['lock_version'], expected_policy_version_id: data.dig('policy', 'id') }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(row.reload.status.phase).to eq('resolved')
    expect(row.lifecycle_transitions.where(action: 'close')).not_to exist
  end

  it 'reports the real calendar dependency and leaves the active policy unchanged' do
    policy = lc_publish(definition: lc_definition(tracked: true))
    version = policy.current_version
    digest = version.digest
    row = sd_ticket
    get "#{base}/tickets/#{row.id}/lifecycle", headers: headers
    expect(response.parsed_body['unavailable_reason']).to eq('calendar_snapshot_required')
    expect(response.parsed_body.fetch('closure_options')).to be_empty
    expect(row.lifecycle_transitions).to be_empty
    expect(version.reload.digest).to eq(digest)
  end

  it 'explains a mandatory service approval without bypassing it or recording a transition' do
    service = JrcServiceDesk::Service.create!(account: sd_account, unit: sd_unit, name: 'Synthetic approval service', code: 'approval', active: true, approval_required: true)
    lc_publish(service: service)
    row = sd_ticket(service: service)
    get "#{base}/tickets/#{row.id}/lifecycle", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['closure_unavailable_reason']).to eq('service_approval_required')
    expect(response.parsed_body['closure_options']).to be_empty
    expect(row.lifecycle_transitions).to be_empty
    expect(service.reload.approval_required?).to be(true)
    sd_account_user.update!(role: :agent, custom_role: create(:custom_role, account: sd_account,
      permissions: %w[jrc_service_desk_module_view jrc_service_desk_tickets_view jrc_service_desk_sla_view jrc_service_desk_history_view jrc_service_desk_notes_view]))
    get "#{base}/tickets/#{row.id}/lifecycle", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['closure_unavailable_reason']).to be_nil
  end

  it 'does not offer closure after permission revocation and rejects unauthenticated requests' do
    lc_publish
    row = sd_ticket
    sd_account_user.update!(role: :agent, custom_role: create(:custom_role, account: sd_account,
      permissions: %w[jrc_service_desk_module_view jrc_service_desk_tickets_view jrc_service_desk_sla_view jrc_service_desk_history_view jrc_service_desk_notes_view jrc_service_desk_resolve]))
    get "#{base}/tickets/#{row.id}/lifecycle", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('options').map { |option| option['action'] }).to include('resolve')
    expect(response.parsed_body.fetch('closure_options')).to be_empty
    get "#{base}/tickets/#{row.id}/lifecycle"
    expect(response).to have_http_status(:unauthorized)
    expect(row.lifecycle_transitions).to be_empty
  end
end

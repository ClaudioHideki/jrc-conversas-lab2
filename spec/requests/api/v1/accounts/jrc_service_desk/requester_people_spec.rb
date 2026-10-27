# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Global Service Desk company and people intake', type: :request do
  include_context 'JRC Service Desk domain'
  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:company) { sd_account.master_companies.create!(name: 'Cliente sintético Alfa', relationship_type: 'customer', person_kind: 'organization') }
  let(:other_company) { sd_account.master_companies.create!(name: 'Cliente sintético Beta', relationship_type: 'customer', person_kind: 'organization') }
  let(:linked) { create(:contact, account: sd_account, company_id: company.id, name: 'Pessoa Alfa') }
  let(:unlinked) { create(:contact, account: sd_account, name: 'Pessoa sem empresa', identifier: 'pessoa-oficial-42') }
  let(:body) { { unit_id: sd_unit.id, company_id: company.id, request_key: 'registration-unique-42',
                contact: { name: 'Nova pessoa sintética', email: 'nova@disposable-mail.invalid' } } }

  before do
    sd_account.enable_features!('jrc_customer_master')
  end

  it 'lists people of several companies without requiring previous tickets' do
    linked
    other = create(:contact, account: sd_account, company_id: other_company.id)
    [company, other_company].each do |record|
      get "#{base}/requesters", params: { unit_id: sd_unit.id, company_id: record.id }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['items'].map { |row| row['id'] }).to eq([record == company ? linked.id.to_s : other.id.to_s])
    end
  end

  it 'returns an explicit empty collection for a company without eligible people' do
    create(:contact, account: sd_account, company_id: company.id, additional_attributes: { entity_type: 'company' })
    get "#{base}/requesters", params: { unit_id: sd_unit.id, company_id: company.id }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.values_at('items', 'meta')).to eq([[], { 'total' => 0, 'page' => 1, 'per_page' => 20 }])
  end

  it 'searches canonical people by identifier and normalizes phone searching' do
    unlinked.update!(phone_number: '+5511999990042')
    ['pessoa-oficial-42', '(11) 99999-0042'].each do |term|
      get "#{base}/requester_people", params: { unit_id: sd_unit.id, company_id: company.id, q: term }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['items'].map { |row| row['id'] }).to include(unlinked.id)
    end
  end

  it 'requires confirmation before linking and never creates a ticket' do
    patch "#{base}/requester_people/#{unlinked.id}/link", params: { unit_id: sd_unit.id, company_id: company.id }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(unlinked.reload.company_id).to be_nil
    expect do
      patch "#{base}/requester_people/#{unlinked.id}/link", params: { unit_id: sd_unit.id, company_id: company.id, confirm: true }, headers: headers, as: :json
    end.to change { JrcCrm::AuditEvent.where(event_type: 'customer_contact_linked').count }.by(1)
    expect(response).to have_http_status(:ok)
    expect(unlinked.reload.company_id).to eq(company.id)
    expect(JrcServiceDesk::Ticket.count).to eq(0)
    expect(response.parsed_body.dig('person', 'requester_eligible')).to be(true)
  end

  it 'instantiates only the requested page as the searchable directory grows' do
    auth_headers = headers
    params = { unit_id: sd_unit.id, q: 'Picker pagination', per_page: 2 }
    company_id = company.id
    counts = [1, 9].map do |size|
      (sd_account.contacts.count...size).each do |index|
        create(:contact, account: sd_account, company_id: company_id, name: format('Picker pagination %02d', index))
      end
      instantiated = 0
      subscriber = lambda do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        instantiated += event.payload[:record_count] if event.payload[:class_name] == 'Contact'
      end
      ActiveSupport::Notifications.subscribed(subscriber, 'instantiation.active_record') do
        get "#{base}/requester_people", params: params, headers: auth_headers
      end
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['meta']).to eq('total' => size, 'page' => 1, 'per_page' => 2)
      expect(response.parsed_body['items'].size).to eq([size, 2].min)
      instantiated
    end
    expect(counts).to eq([1, 2])
  end

  it 'batches company names for the selected page while preserving order and total' do
    first = create(:contact, account: sd_account, company_id: company.id, name: 'Picker batch A')
    second = create(:contact, account: sd_account, company_id: other_company.id, name: 'Picker batch B')
    third = create(:contact, account: sd_account, company_id: company.id, name: 'Picker batch C')
    fourth = create(:contact, account: sd_account, company_id: other_company.id, name: 'Picker batch D')
    auth_headers = headers
    params = { unit_id: sd_unit.id, q: 'Picker batch', per_page: 2, page: 2 }
    company_queries = []
    subscriber = lambda do |*args|
      event = ActiveSupport::Notifications::Event.new(*args)
      sql = event.payload[:sql]
      company_queries << sql if sql.include?('SELECT "companies"."id", "companies"."name" FROM "companies"')
    end
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      get "#{base}/requester_people", params: params, headers: auth_headers
    end
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['items'].map { |row| row.values_at('id', 'company_name') }).to eq(
      [[third.id, company.name], [fourth.id, other_company.name]]
    )
    expect(response.parsed_body['items'].map { |row| row['id'] }).not_to include(first.id, second.id)
    expect(response.parsed_body['meta']).to eq('total' => 4, 'page' => 2, 'per_page' => 2)
    expect(company_queries.size).to eq(1)

    get "#{base}/requester_people", params: params.merge(page: 3), headers: auth_headers
    expect(response.parsed_body['items']).to eq([])
    expect(response.parsed_body['meta']).to eq('total' => 4, 'page' => 3, 'per_page' => 2)
  end

  it 'preserves tenant and corporate coverage in page items and totals for an authorized custom role' do
    permissions = %w[contact_manage jrc_service_desk_module_view jrc_service_desk_tickets_view jrc_service_desk_customers_view
                     jrc_service_desk_lookups_view]
    sd_account_user.update!(custom_role: create(:custom_role, account: sd_account, permissions: permissions))
    linked
    unlinked
    restricted = sd_account.master_companies.create!(name: 'Restricted picker company', relationship_type: 'internal', person_kind: 'organization')
    create(:contact, account: sd_account, company_id: restricted.id)
    create(:contact, account: sd_foreign_account)
    get "#{base}/requester_people", params: { unit_id: sd_unit.id, per_page: 1, page: 2 }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['items'].map { |row| row['id'] }).to eq([unlinked.id])
    expect(response.parsed_body['meta']).to eq('total' => 2, 'page' => 2, 'per_page' => 1)
    expect(response.parsed_body['items'].first['can_link']).to be(false)

    get "#{base}/requester_people", params: { unit_id: sd_unit.id, company_id: restricted.id }, headers: headers
    expect(response).to have_http_status(:not_found)
    sd_account_user.custom_role.update!(permissions: permissions - ['contact_manage'])
    get "#{base}/requester_people", params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:forbidden)
  end

  it 'searches a formatted secondary phone without returning all coworkers of the matched person' do
    linked
    colleague = create(:contact, account: sd_account, company_id: company.id, name: 'Colega sintético')
    JrcCustomers::ContactPoint.create!(account: sd_account, contact: linked, kind: 'mobile', value: '+5511999980042')
    get "#{base}/requesters", params: { unit_id: sd_unit.id, company_id: company.id, q: '(11) 99998-0042' }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['items'].map { |row| row['id'] }).to eq([linked.id.to_s])
    get "#{base}/requester_people", params: { unit_id: sd_unit.id, company_id: company.id, q: 'Pessoa Alfa' }, headers: headers
    expect(response.parsed_body['items'].map { |row| row['id'] }).to eq([linked.id])
    expect(response.body).not_to include(colleague.name)
  end

  it 'does not duplicate the link or audit on repeated confirmation' do
    2.times do
      patch "#{base}/requester_people/#{unlinked.id}/link", params: { unit_id: sd_unit.id, company_id: company.id, confirm: true }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
    end
    expect(JrcCrm::AuditEvent.where(event_type: 'customer_contact_linked', resource_id: unlinked.id).count).to eq(1)
  end

  it 'preserves another company relationship rather than inventing multiple-company support' do
    linked
    patch "#{base}/requester_people/#{linked.id}/link", params: { unit_id: sd_unit.id, company_id: other_company.id, confirm: true }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['code']).to eq('REQUESTER_REVIEW_REQUIRED')
    expect(linked.reload.company_id).to eq(company.id)
  end

  it 'creates and rereads a canonical person without sending a ticket' do
    expect do
      post "#{base}/requester_people", params: body, headers: headers, as: :json
    end.to change(Contact, :count).by(1)
    expect(response).to have_http_status(:created)
    id = response.parsed_body.dig('person', 'id')
    person = Contact.find(id)
    expect(person.company_id).to eq(company.id)
    expect(person.additional_attributes['entity_type']).to eq('person')
    expect(JrcServiceDesk::Ticket.count).to eq(0)
    get "#{base}/requester_people/#{id}", params: { unit_id: sd_unit.id, company_id: company.id }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('person', 'name')).to eq(body[:contact][:name])
  end

  it 'requires only the name according to the official Contact model' do
    post "#{base}/requester_people", params: body.merge(contact: { name: 'Pessoa sem telefone ou email' }), headers: headers, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig('person', 'email')).to be_nil
  end

  it 'replays creation without duplication and rejects a changed body with the same key' do
    ids = 2.times.map do
      post "#{base}/requester_people", params: body, headers: headers, as: :json
      expect(response).to have_http_status(:created)
      response.parsed_body.dig('person', 'id')
    end
    expect(ids.uniq.size).to eq(1)
    post "#{base}/requester_people", params: body.merge(contact: { name: 'Pessoa diferente' }), headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(sd_account.contacts.count).to eq(1)
  end

  it 'offers duplicate candidates without creating or merging a contact' do
    unlinked.update!(email: body[:contact][:email])
    expect do
      post "#{base}/requester_people", params: body, headers: headers, as: :json
    end.not_to change(Contact, :count)
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['code']).to eq('POSSIBLE_DUPLICATE')
    expect(response.parsed_body['candidates'].map { |row| row['id'] }).to include(unlinked.id)
    expect(unlinked.reload.company_id).to be_nil
  end

  it 'requires review for ambiguous names even without a shared telephone' do
    unlinked.update!(name: body[:contact][:name])
    post "#{base}/requester_people", params: body, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(sd_account.contacts.count).to eq(1)
  end

  it 'allows explicitly confirmed different people with the same name but never duplicate identities' do
    unlinked.update!(name: body[:contact][:name])
    post "#{base}/requester_people", params: body, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['allow_distinct']).to be(true)
    post "#{base}/requester_people", params: body.merge(confirm_distinct: true), headers: headers, as: :json
    expect(response).to have_http_status(:created)
    expect(sd_account.contacts.count).to eq(2)
    post "#{base}/requester_people", params: body.merge(request_key: 'another-identity-attempt', confirm_distinct: true), headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['allow_distinct']).to be(false)
    expect(sd_account.contacts.count).to eq(2)
  end

  it 'never returns or links contacts belonging to an internal company outside corporate coverage' do
    restricted = sd_account.master_companies.create!(name: 'Empresa interna fora do escopo', relationship_type: 'internal', person_kind: 'organization')
    hidden = create(:contact, account: sd_account, company_id: restricted.id, name: 'Pessoa restrita')
    get "#{base}/requester_people", params: { unit_id: sd_unit.id, company_id: company.id, q: 'Pessoa restrita' }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['items']).to be_empty
    patch "#{base}/requester_people/#{hidden.id}/link", params: { unit_id: sd_unit.id, company_id: company.id, confirm: true }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(hidden.reload.company_id).to eq(restricted.id)
    post "#{base}/tickets", params: { unit_id: sd_unit.id, ticket: sd_create_attributes.merge(requester_id: hidden.id) },
         headers: headers.merge('Idempotency-Key' => 'restricted-requester-without-company'), as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcServiceDesk::Ticket.count).to eq(0)
  end

  it 'rejects organization, technical and unclassified imported contacts without modifying identifiers' do
    contacts = [
      create(:contact, account: sd_account, company_id: company.id, additional_attributes: { entity_type: 'company' }),
      create(:contact, account: sd_account, company_id: company.id, identifier: 'bemtevi:customer:1234'),
      create(:contact, account: sd_account, company_id: company.id, additional_attributes: { entity_type: 'technical' }),
      create(:contact, account: sd_account, company_id: company.id, additional_attributes: { source_system: 'veccio', source_id: '42' })
    ]
    contacts.each do |contact|
      before = contact.reload.attributes.deep_dup
      get "#{base}/requester_people/#{contact.id}", params: { unit_id: sd_unit.id, company_id: company.id }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expected_code = JrcCustomers::RequesterIdentity.reason(contact) == 'organization' ? 'requester_is_company' : 'requester_review_required'
      expect(response.parsed_body['code']).to eq(expected_code)
      patch "#{base}/requester_people/#{contact.id}/link", params: { unit_id: sd_unit.id, company_id: company.id, confirm: true }, headers: headers, as: :json
      expect(response).to have_http_status(:conflict)
      expect(contact.reload.attributes).to eq(before)
    end
    get "#{base}/requesters", params: { unit_id: sd_unit.id, company_id: company.id }, headers: headers
    expect(response.parsed_body['items']).to be_empty
  end

  it 'accepts an explicitly classified imported person and a native person whose name resembles a company' do
    [create(:contact, account: sd_account, company_id: company.id, additional_attributes: { entity_type: 'person', source_system: 'veccio' }),
     create(:contact, account: sd_account, company_id: company.id, name: company.name)].each do |contact|
      get "#{base}/requester_people/#{contact.id}", params: { unit_id: sd_unit.id, company_id: company.id }, headers: headers
      expect(response).to have_http_status(:ok)
    end
  end

  it 'validates relationships on company changes without writing to people' do
    before = linked.reload.attributes.deep_dup
    get "#{base}/requester_people/#{linked.id}", params: { unit_id: sd_unit.id, company_id: other_company.id }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('requester_company_mismatch')
    get "#{base}/requester_people/#{linked.id}", params: { unit_id: sd_unit.id, company_id: company.id }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(linked.reload.attributes).to eq(before)
  end

  it 'rejects unauthenticated and cross-account create, read and link requests without writes' do
    foreign = create(:contact, account: sd_foreign_account)
    post "#{base}/requester_people", params: body, as: :json
    expect(response).to have_http_status(:unauthorized)
    get "#{base}/requester_people/#{foreign.id}", params: { unit_id: sd_unit.id, company_id: company.id }, headers: headers
    expect(response).to have_http_status(:not_found)
    patch "#{base}/requester_people/#{foreign.id}/link", params: { unit_id: sd_unit.id, company_id: company.id, confirm: true }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(foreign.reload.company_id).to be_nil
  end

  it 'honors contact management permission and foreign unit/company restrictions' do
    unlinked
    foreign_company = sd_foreign_account.master_companies.create!(name: 'Empresa estrangeira', relationship_type: 'customer', person_kind: 'organization')
    [body.merge(company_id: foreign_company.id), body.merge(unit_id: sd_foreign_unit.id)].each do |payload|
      post "#{base}/requester_people", params: payload, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
    sd_account_user.update!(custom_role: create(:custom_role, account: sd_account,
      permissions: %w[jrc_service_desk_module_view jrc_service_desk_tickets_view jrc_service_desk_tickets_create jrc_service_desk_customers_view jrc_service_desk_lookups_view]))
    expect do
      post "#{base}/requester_people", params: body, headers: headers, as: :json
    end.not_to change(Contact, :count)
    expect(response).to have_http_status(:forbidden)
    patch "#{base}/requester_people/#{unlinked.id}/link", params: { unit_id: sd_unit.id, company_id: company.id, confirm: true }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(unlinked.reload.company_id).to be_nil
  end

  it 'rejects invalid person payloads without accepting injected entity or privilege fields' do
    [{ name: '' }, { name: 'Invalid phone', phone_number: 'not-a-phone' }, { name: 'Escalation', account_id: sd_foreign_account.id },
     { name: 'Entity injection', additional_attributes: { entity_type: 'person' } }].each do |contact|
      expect do
        post "#{base}/requester_people", params: body.merge(contact: contact), headers: headers, as: :json
      end.not_to change(Contact, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it 'lists and paginates all eligible companies including those without contacts' do
    17.times { |n| sd_account.master_companies.create!(name: format('Cliente pagina %02d', n), relationship_type: 'customer', person_kind: 'organization') }
    get "/api/v1/accounts/#{sd_account.id}/customers/companies", params: { q: 'Cliente pagina', page: 2, per_page: 15 }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['meta']['total']).to eq(17)
    expect(response.parsed_body['payload'].size).to eq(2)
    expect(response.parsed_body['payload'].all? { |record| record['contact_count'] == 0 }).to be(true)
  end

  it 'creates a full ticket and replays it with the linked person while keeping an internal agent separate' do
    sd_as_admin!
    linked
    create_body = { unit_id: sd_unit.id, ticket: sd_create_attributes.merge(requester_id: linked.id, company_id: company.id,
      assignee_account_user_id: sd_account_user.id) }
    2.times do
      post "#{base}/tickets", params: create_body, headers: headers.merge('Idempotency-Key' => 'global-person-ticket-42'), as: :json
      expect(response).to have_http_status(:created)
    end
    ticket = JrcServiceDesk::Ticket.sole
    expect(ticket.requester).to eq(linked)
    expect(ticket.company_id).to eq(company.id)
    expect(ticket.assignee_membership).to eq(sd_membership)
    expect(sd_account.contacts.where(email: sd_user.email)).not_to exist
  end

  it 'keeps a valid ticket unassigned when no eligible automatic agent exists' do
    sd_as_admin!
    sd_membership.update!(availability: 'unavailable')
    queue = create(:jrc_sd_queue, unit: sd_unit, distribution_mode: 'least_load')
    post "#{base}/tickets", params: { unit_id: sd_unit.id, ticket: sd_create_attributes.merge(queue_id: queue.id) },
         headers: headers.merge('Idempotency-Key' => 'unassigned-ticket-42'), as: :json
    expect(response).to have_http_status(:created)
    expect(JrcServiceDesk::Ticket.sole.assignee_membership_id).to be_nil
  end
end

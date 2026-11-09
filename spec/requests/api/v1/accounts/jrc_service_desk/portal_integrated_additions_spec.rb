# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Portal routing, shared requester channels and authorized establishments', type: :request do
  include_context 'JRC Service Desk domain'
  let(:company) { sd_account.master_companies.create!(name: 'Synthetic customer', relationship_type: 'customer') }
  let(:sd_contact) { create(:contact, account: sd_account, company_id: company.id, identifier: SecureRandom.uuid) }
  let(:widget) { create(:channel_widget, account: sd_account) }
  let(:identity) { create(:contact_inbox, contact: sd_contact, inbox: widget.inbox, hmac_verified: true) }
  let(:portal_user) { create(:user) }
  let(:establishment) do
    sd_account.master_companies.create!(name: 'Synthetic store', tax_id: '11222333000181',
      additional_attributes: { 'jrc_establishment' => { 'store_code' => '030', 'cluster' => 'Synthetic cluster', 'phones' => [] } })
  end
  let(:grant) do
    JrcServiceDesk::PortalGrant.create!(account: sd_account, user: portal_user, granted_by: sd_user, company: company,
      contact: sd_contact, contact_inbox: identity, inbox: widget.inbox, active: true, establishment_ids: [establishment.id])
  end
  let(:service) do
    JrcServiceDesk::Service.create!(account: sd_account, unit: sd_unit, code: 'integrated-portal', name: 'Selected customer service',
      active: true, portal_enabled: true, default_priority: sd_priority, portal_inbox: widget.inbox, portal_execution_membership: sd_membership)
  end
  let(:headers) do
    token = Widget::TokenService.new(payload: { source_id: identity.source_id, inbox_id: widget.inbox.id }).generate_token
    { 'X-Auth-Token' => token, 'Idempotency-Key' => 'integrated-portal-create', 'X-Service-Desk-Identifier' => sd_contact.identifier,
      'X-Service-Desk-Identity-Token' => OpenSSL::HMAC.hexdigest('sha256', widget.hmac_token, sd_contact.identifier) }
  end
  let(:values) do
    { service_id: service.id, service_revision: JrcServiceDesk::ConfigurationResources.revision('services', service),
      title: 'Store needs support', description: 'Synthetic request', service_fields: {}, establishment_company_id: establishment.id }
  end

  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master')
    sd_account.update!(internal_attributes: sd_account.internal_attributes.merge('requester_portal_enabled' => true))
    sd_status
  end

  it 'preserves the normal form and creation for a requester without store grants in the same unit' do
    grant.update!(establishment_ids: [])
    JrcServiceDesk::PortalRoutingConfiguration.save!(unit: sd_unit, actor: sd_account_user, values: { 'stores_enabled' => true },
      expected_revision: JrcServiceDesk::PortalRoutingConfiguration.revision(sd_unit))
    service
    get '/api/v1/widget/service_desk/services', params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('services').find { |row| row['id'] == service.id.to_s }.fetch('stores_enabled')).to be(false)
    post '/api/v1/widget/service_desk/tickets', params: { website_token: widget.website_token, ticket: values.except(:establishment_company_id) }, headers: headers, as: :json
    expect(response).to have_http_status(:created), response.body
  end

  it 'requires a selected store only for a requester with explicit store grants' do
    grant
    JrcServiceDesk::PortalRoutingConfiguration.save!(unit: sd_unit, actor: sd_account_user, values: { 'stores_enabled' => true },
      expected_revision: JrcServiceDesk::PortalRoutingConfiguration.revision(sd_unit))
    service
    get '/api/v1/widget/service_desk/services', params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('services').find { |row| row['id'] == service.id.to_s }.fetch('stores_enabled')).to be(true)
    post '/api/v1/widget/service_desk/tickets', params: { website_token: widget.website_token, ticket: values.except(:establishment_company_id) }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(sd_account.conversations).to be_empty
  end

  it 'creates one ticket for the selected store and preserves requester, company and service on replay after configuration changes' do
    grant
    queue = create(:jrc_sd_queue, unit: sd_unit, distribution_mode: 'manual')
    JrcServiceDesk::PortalRoutingConfiguration.save!(unit: sd_unit, actor: sd_account_user,
      values: { 'queue_id' => queue.id, 'stores_enabled' => true }, expected_revision: JrcServiceDesk::PortalRoutingConfiguration.revision(sd_unit))
    post '/api/v1/widget/service_desk/tickets', params: { website_token: widget.website_token, ticket: values }, headers: headers, as: :json
    expect(response).to have_http_status(:created), response.body
    ticket = JrcServiceDesk::Ticket.find(response.parsed_body.dig('ticket', 'id'))
    expect(ticket).to have_attributes(requester_id: sd_contact.id, company_id: company.id, establishment_company_id: establishment.id,
                                      service_id: service.id, queue_id: queue.id, unit_id: sd_unit.id)
    expect(ticket.catalogue_snapshot.dig('establishment', 'store_code')).to eq('030')
    original_store_snapshot = ticket.catalogue_snapshot.fetch('establishment').deep_dup
    establishment.update!(name: 'Renamed store')
    context = JrcServiceDesk::OperationalContext.new(sd_context)
    JrcServiceDesk::TicketCatalogue.new(ticket, context: context).bind!({})
    expect(ticket.catalogue_snapshot.fetch('establishment')).to eq(original_store_snapshot)
    JrcServiceDesk::PortalRoutingConfiguration.save!(unit: sd_unit, actor: sd_account_user, values: {},
      expected_revision: JrcServiceDesk::PortalRoutingConfiguration.revision(sd_unit))
    expect do
      post '/api/v1/widget/service_desk/tickets', params: { website_token: widget.website_token, ticket: values }, headers: headers, as: :json
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response).to have_http_status(:created), response.body
    expect(response.parsed_body.dig('ticket', 'id')).to eq(ticket.id.to_s)
  end

  it 'rejects a store not explicitly granted without partially creating a ticket or conversation' do
    grant.update!(establishment_ids: [])
    JrcServiceDesk::PortalRoutingConfiguration.save!(unit: sd_unit, actor: sd_account_user, values: { 'stores_enabled' => true },
      expected_revision: JrcServiceDesk::PortalRoutingConfiguration.revision(sd_unit))
    expect do
      post '/api/v1/widget/service_desk/tickets', params: { website_token: widget.website_token, ticket: values }, headers: headers, as: :json
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response).to have_http_status(:not_found)
    expect(sd_account.conversations).to be_empty
  end

  it 'lists only active explicitly authorized stores and rejects cross-account grant changes' do
    grant
    hidden = sd_account.master_companies.create!(name: 'Other store', additional_attributes: { 'jrc_establishment' => { 'store_code' => '999' } })
    foreign = sd_foreign_account.master_companies.create!(name: 'Foreign store', additional_attributes: { 'jrc_establishment' => { 'store_code' => '888' } })
    expect { grant.update!(establishment_ids: [foreign.id]) }.to raise_error(ActiveRecord::RecordInvalid)
    grant.reload
    JrcServiceDesk::PortalRoutingConfiguration.save!(unit: sd_unit, actor: sd_account_user, values: { 'stores_enabled' => true },
      expected_revision: JrcServiceDesk::PortalRoutingConfiguration.revision(sd_unit))
    get "/api/v1/widget/service_desk/services/#{service.id}/establishments", params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('establishments').map { |row| row['id'] }).to eq([establishment.id.to_s])
    expect(response.body).not_to include(hidden.name, foreign.name)
    establishment.update!(active: false)
    get "/api/v1/widget/service_desk/services/#{service.id}/establishments", params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('establishments')).to be_empty
    post '/api/v1/widget/service_desk/tickets', params: { website_token: widget.website_token, ticket: values }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcServiceDesk::Ticket.where(account: sd_account)).to be_empty
  end

  it 'rolls back creation when the configured manual destination is later disabled' do
    queue = create(:jrc_sd_queue, unit: sd_unit, distribution_mode: 'manual')
    JrcServiceDesk::PortalRoutingConfiguration.save!(unit: sd_unit, actor: sd_account_user, values: { 'queue_id' => queue.id },
      expected_revision: JrcServiceDesk::PortalRoutingConfiguration.revision(sd_unit))
    queue.update!(active: false)
    post '/api/v1/widget/service_desk/tickets', params: { website_token: widget.website_token, ticket: values.except(:establishment_company_id) }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcServiceDesk::Ticket.where(account: sd_account)).to be_empty
    expect(sd_account.conversations).to be_empty
  end

  it 'assigns manually without automatic availability or capacity and derives the queue team' do
    team = create(:team, account: sd_account)
    agent = create(:user, account: sd_account)
    create(:team_member, team: team, user: agent)
    membership = create(:jrc_sd_membership, unit: sd_unit, account_user: sd_account.account_users.find_by!(user: agent),
      availability: 'unavailable', capacity: nil, manual_assignment_enabled: true)
    queue = create(:jrc_sd_queue, unit: sd_unit, team: team, distribution_mode: 'manual')
    JrcServiceDesk::PortalRoutingConfiguration.save!(unit: sd_unit, actor: sd_account_user,
      values: { 'queue_id' => queue.id, 'assignee_account_user_id' => membership.account_user_id },
      expected_revision: JrcServiceDesk::PortalRoutingConfiguration.revision(sd_unit))
    input = values.except(:establishment_company_id)
    post '/api/v1/widget/service_desk/tickets', params: { website_token: widget.website_token, ticket: input }, headers: headers, as: :json
    expect(response).to have_http_status(:created), response.body
    ticket = JrcServiceDesk::Ticket.find(response.parsed_body.dig('ticket', 'id'))
    expect(ticket).to have_attributes(assignee_membership_id: membership.id, team_id: team.id, queue_id: queue.id, service_id: service.id)
    expect(membership.reload).to have_attributes(availability: 'unavailable', capacity: nil)
    expect(queue.reload.distribution_mode).to eq('manual')
  end

  it 'rejects another unit queue and stale administrative revisions atomically' do
    queue = create(:jrc_sd_queue, unit: sd_other_unit)
    revision = JrcServiceDesk::PortalRoutingConfiguration.revision(sd_unit)
    expect do
      JrcServiceDesk::PortalRoutingConfiguration.save!(unit: sd_unit, actor: sd_account_user, values: { 'queue_id' => queue.id }, expected_revision: revision)
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcServiceDesk::PortalRoutingConfiguration.read(sd_unit)).to eq({})
    expect do
      JrcServiceDesk::PortalRoutingConfiguration.save!(unit: sd_unit, actor: sd_account_user, values: {}, expected_revision: 'stale')
    end.to raise_error(JrcServiceDesk::IdempotencyConflict)
  end

  it 'keeps three people with shared channels distinct and reuses only an exact registration retry' do
    writer = JrcCustomers::RequesterWriter.new(account: sd_account, actor: sd_user)
    people = %w[Joao Maria Pedro].map do |name|
      writer.create!(company: company, attributes: { 'name' => name, 'email' => 'shared@example.test', 'phone_number' => '(61) 99999-9999' }, request_key: name)
    end
    expect(people.map(&:id).uniq.size).to eq(3)
    expect(people.map(&:identifier).uniq.size).to eq(3)
    people.each do |person|
      expect(JrcServiceDesk::RequesterContactDetails.call(person)).to include('email' => 'shared@example.test', 'phone_number' => '+5561999999999')
      expect(JrcServiceDesk::RequesterContactDetails.notification_recipient(person, 'email')).to be_nil
    end
    repeated = writer.create!(company: company, attributes: { 'name' => 'Joao', 'email' => 'shared@example.test', 'phone_number' => '(61) 99999-9999' }, request_key: 'Joao')
    expect(repeated.id).to eq(people.first.id)
  end

  it 'preserves store metadata, all phones and a textual leading-zero code through the native company writer' do
    result = JrcCustomers::CompanyWriter.new(account: sd_account, actor: sd_user).save!(company: establishment,
      attributes: { establishment: { 'store_code' => '030', 'cluster' => 'Synthetic cluster', 'phones' => ['(16) 4042-2968', '(16) 3636-6367'] } })
    expect(JrcCustomers::EstablishmentMetadata.read(result.reload)).to include('store_code' => '030', 'phones' => %w[+551640422968 +551636366367])
    expect(result.customer_code).to start_with('EMP-')
  end
end

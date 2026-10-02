require 'rails_helper'

# Native DB specs: run only after applying the THREE additive migrations to TEST.
RSpec.describe 'Customer master on official operations modules' do
  include_context 'JRC Service Desk domain'
  let(:company) { sd_account.master_companies.create!(name: 'Customer master test') }
  let(:other_company) { sd_account.master_companies.create!(name: 'Other master test') }
  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_projects', 'jrc_crm')
    sd_contact.update!(company_id: company.id)
  end
  def create_ticket(attributes = {}, key: SecureRandom.uuid, **extra)
    attributes = attributes.merge(extra)
    JrcServiceDesk::CreateTicketService.new(user_context: sd_context).call(
      unit_id: sd_unit.id, attributes: sd_create_attributes.merge(attributes), idempotency_key: key)
  end
  def create_project(attributes = {})
    JrcProjects::Projects::Create.call(account: sd_account, actor: sd_user,
      attributes: { name: 'Project master test', contact_id: sd_contact.id }.merge(attributes), idempotency_key: SecureRandom.uuid)
  end
  def context
    JrcCustomers::Customer360.new(account: sd_account, user: sd_user, account_user: sd_account_user, company: company)
  end

  it 'uses the companies table and existing requester without another customer registry' do
    ticket = create_ticket
    expect(ticket.company_id).to eq(company.id)
    expect(ticket.requester_id).to eq(sd_contact.id)
    expect(ticket.operator_company_id).to eq(sd_operator.id)
    expect(ticket.master_company.class.table_name).to eq('companies')
  end
  it 'preserves lifecycle and audit creation' do
    ticket = create_ticket(company_id: company.id)
    expect(ticket.ticket_events.pluck(:event_type)).to include('ticket_created')
    expect(ticket.created_by_membership_id).to eq(sd_membership.id)
  end
  it 'rejects a company different from the requester' do
    expect { create_ticket(company_id: other_company.id) }.to raise_error(ActiveRecord::RecordInvalid)
  end
  it 'rejects a company in another tenant' do
    foreign = sd_foreign_account.master_companies.create!(name: 'Foreign')
    expect { create_ticket(company_id: foreign.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end
  it 'includes an explicit company in the native idempotency fingerprint' do
    key = SecureRandom.uuid
    first = create_ticket({ company_id: company.id }, key: key)
    expect(create_ticket({ company_id: company.id }, key: key).id).to eq(first.id)
    expect { create_ticket({ company_id: other_company.id }, key: key) }.to raise_error(JrcServiceDesk::IdempotencyConflict)
  end
  it 'replays a request created with the flag off without altering its old fingerprint' do
    sd_account.disable_features!('jrc_customer_master')
    key = SecureRandom.uuid
    first = create_ticket({}, key: key)
    digest = first.request_fingerprint
    sd_account.enable_features!('jrc_customer_master')
    expect(create_ticket({}, key: key).id).to eq(first.id)
    expect(first.reload.request_fingerprint).to eq(digest)
  end
  it 'does not permit silently clearing the company required by the requester' do
    ticket = create_ticket
    expect do
      JrcServiceDesk::UpdateTicketService.new(user_context: sd_context).call(ticket_id: ticket.id,
        attributes: { company_id: nil }, expected_lock_version: ticket.lock_version)
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(ticket.reload.company_id).to eq(company.id)
  end
  it 'creates the project with the same company while retaining its board and owner' do
    project = create_project
    expect(project.company_id).to eq(company.id)
    expect(project.boards.count).to eq(1)
    expect(project.project_members.find_by!(user: sd_user).role).to eq('owner')
  end
  it 'allows an internal project without a contact or company' do
    project = create_project(contact_id: nil)
    expect(project.contact_id).to be_nil
    expect(project.company_id).to be_nil
  end
  it 'allows a company-level project without creating an unnecessary Contact' do
    sd_contact
    expect { create_project(contact_id: nil, company_id: company.id) }.not_to change(Contact, :count)
  end
  it 'rejects a conflicting project company' do
    expect { create_project(company_id: other_company.id) }.to raise_error(ActiveRecord::RecordInvalid)
  end
  it 'does not reassign historical company links during an unrelated title change' do
    project = create_project
    sd_contact.update!(company_id: other_company.id)
    project.update!(name: 'Title only')
    expect(project.reload.company_id).to eq(company.id)
  end
  it 'aggregates only actual tickets and projects and never substitutes operator IDs' do
    ticket = create_ticket
    project = create_project
    expect(context.tickets.pluck(:id)).to include(ticket.id)
    expect(context.projects.pluck(:id)).to include(project.id)
    expect(context.overview).to include(tickets_open: 1, projects_active: 1)
  end
  it 'does not expose operations counters when their native feature is disabled' do
    create_ticket
    sd_account.disable_features!('jrc_service_desk')
    expect(context.overview).not_to have_key(:tickets_open)
    expect(context.sources).not_to have_key('tickets')
  end
  it 'keeps an explicit unavailable source for native Service Desk tasks' do
    result = JrcOperations::Agenda.new(account_user: sd_account_user, filters: { source: 'service_desk', company_id: company.id }).call
    expect(result[:meta][:unavailable_sources]).to include(service_desk: 'native_tasks_not_available')
    expect(result[:data]).to be_empty
  end
  it 'rejects agenda company filters from another tenant' do
    foreign = sd_foreign_account.master_companies.create!(name: 'Foreign')
    expect { JrcOperations::Agenda.new(account_user: sd_account_user, filters: { company_id: foreign.id }) }.to raise_error(ActiveRecord::RecordNotFound)
  end
  it 'does not write operational links in a dry run' do
    sd_account.disable_features!('jrc_customer_master')
    ticket = create_ticket
    report = JrcCustomers::OperationsBackfill.new(account: sd_account).plan
    expect(report[:pending]).to include(hash_including(id: ticket.id, company_id: company.id))
    expect(ticket.reload.company_id).to be_nil
  end
  it 'requires a reviewed operational plan and preserves fingerprint after apply' do
    sd_account.disable_features!('jrc_customer_master')
    ticket = create_ticket
    fingerprint = ticket.request_fingerprint
    service = JrcCustomers::OperationsBackfill.new(account: sd_account)
    report = service.plan
    service.apply!(reviewed_digest: report[:digest])
    expect(ticket.reload.company_id).to eq(company.id)
    expect(ticket.request_fingerprint).to eq(fingerprint)
    expect(service.plan[:pending]).to be_empty
  end
  it 'refuses a stale backfill plan without writing partial results' do
    sd_account.disable_features!('jrc_customer_master')
    ticket = create_ticket
    service = JrcCustomers::OperationsBackfill.new(account: sd_account)
    report = service.plan
    ticket.update!(title: 'Changed after review')
    expect { service.apply!(reviewed_digest: report[:digest]) }.to raise_error(JrcCustomers::OperationsBackfill::StalePlan)
    expect(ticket.reload.company_id).to be_nil
  end
  it 'preserves requester, project and immutable commercial snapshot references during native merge' do
    ticket = create_ticket
    project = create_project
    order = JrcCrm::SalesOrder.create!(account: sd_account, owner: sd_user, contact: sd_contact, source_type: 'manual', snapshot: { preserved: true })
    contract = JrcCrm::Contract.create!(account: sd_account, owner: sd_user, contact: sd_contact, sales_order: order, status: 'active')
    snapshot = contract.lifecycle_metadata.deep_dup
    base = create(:contact, account: sd_account, company_id: company.id)
    ContactMergeAction.new(account: sd_account, base_contact: base, mergee_contact: sd_contact).perform
    expect(ticket.reload.requester_id).to eq(base.id)
    expect(project.reload.contact_id).to eq(base.id)
    expect(order.reload.contact_id).to eq(base.id)
    expect(order.snapshot).to eq('preserved' => true)
    expect(contract.reload.contact_id).to eq(base.id)
    expect(contract.lifecycle_metadata).to eq(snapshot)
  end
  it 'includes the real commercial contract in Customer360 without changing its content' do
    order = JrcCrm::SalesOrder.create!(account: sd_account, owner: sd_user, contact: sd_contact, source_type: 'manual')
    contract = JrcCrm::Contract.create!(account: sd_account, owner: sd_user, contact: sd_contact, sales_order: order, status: 'active')
    expect(context.contracts.pluck(:id)).to eq([contract.id])
    expect(context.overview[:contracts_active]).to eq(1)
  end
  it 'refuses native merge source deletion when a native reassignment was not successful' do
    source = sd_contact
    base = create(:contact, account: sd_account, company_id: company.id)
    inbox = create(:inbox, account: sd_account)
    create(:contact_inbox, contact: source, inbox: inbox)
    action = ContactMergeAction.new(account: sd_account, base_contact: base, mergee_contact: source)
    allow(action).to receive(:merge_contact_inboxes) # Simulate native update returning false.
    expect { action.perform }.to raise_error(JrcCustomers::MergePreserver::Conflict)
    expect(Contact.exists?(source.id)).to be(true)
  end
end

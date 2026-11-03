require 'rails_helper'

RSpec.describe 'Native contact merge with master preservation' do
  let(:account) { create(:account) }
  let(:owner) { create(:user, account: account) }
  let(:base) { create(:contact, account: account, name: 'Base') }
  let(:source) { create(:contact, account: account, name: 'Source', email: 'source@example.test') }
  before { account.enable_features!('jrc_customer_master', 'jrc_crm') }
  def merge
    ContactMergeAction.new(account: account, base_contact: base, mergee_contact: source).perform
  end

  it 'preserves CRM lead references and source email in supplemental points' do
    lead = JrcCrm::Lead.create!(account: account, owner: owner, name: 'Lead', contact: source)
    merge
    expect(lead.reload.contact_id).to eq(base.id)
    expect(Contact.exists?(source.id)).to be(false)
    expect(base.contact_points.where(normalized_value: 'source@example.test')).to exist
  end
  it 'keeps the provider/source identity while moving ContactInbox to the survivor' do
    inbox = create(:inbox, account: account)
    link = create(:contact_inbox, contact: source, inbox: inbox, source_id: 'provider-source-preserved')
    merge
    expect(link.reload.contact_id).to eq(base.id)
    expect(link.source_id).to eq('provider-source-preserved')
  end
  it 'writes a source snapshot in the existing audit table' do
    id = source.id
    merge
    event = JrcCrm::AuditEvent.where(account: account, resource_id: base.id, event_type: 'customer_contact_merged').first
    expect(event.metadata['source_contact_id']).to eq(id)
    expect(event.metadata['source_snapshot']['name']).to eq('Source')
  end
  it 'blocks a merge between different company memberships without deleting either contact' do
    base.update!(company_id: account.master_companies.create!(name: 'A').id)
    source.update!(company_id: account.master_companies.create!(name: 'B').id)
    expect { merge }.to raise_error(JrcCustomers::MergePreserver::Conflict)
    expect(Contact.where(id: [base.id, source.id]).count).to eq(2)
  end
  it 'blocks conflicting external identifiers' do
    base.update!(identifier: 'external-a')
    source.update!(identifier: 'external-b')
    expect { merge }.to raise_error(JrcCustomers::MergePreserver::Conflict)
  end

  it 'retains company role, job fields and the unique primary when the linked source is merged into an unlinked survivor' do
    company = account.master_companies.create!(name: 'TESTE SINTÉTICO — Empresa da fusão')
    source.update!(company_id: company.id)
    source.update!(job_title: 'Diretora', department: 'Compras', company_role: 'purchasing', company_primary: true)
    merge
    expect(base.reload.attributes.slice('company_id', 'job_title', 'department', 'company_role', 'company_primary'))
      .to eq('company_id' => company.id, 'job_title' => 'Diretora', 'department' => 'Compras',
             'company_role' => 'purchasing', 'company_primary' => true)
    expect(account.contacts.where(company_id: company.id, company_primary: true).pluck(:id)).to eq([base.id])
    event = JrcCrm::AuditEvent.where(account: account, resource_id: base.id, event_type: 'customer_contact_merged').first
    expect(event.metadata.dig('source_snapshot', 'company_primary')).to be(true)
    expect(Contact.exists?(source.id)).to be(false)
  end
end

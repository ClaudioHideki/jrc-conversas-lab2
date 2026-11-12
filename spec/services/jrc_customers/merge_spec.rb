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

  it 'retains source segment choices when the feature was subsequently disabled' do
    taxonomy = JrcCustomers::Taxonomy.create!(account: account, kind: 'segment', name: 'TESTE — Escolha da origem')
    choice = JrcCustomers::SegmentOverride.create!(account: account, taxonomy: taxonomy, contact: source, mode: 'include')
    account.disable_features!('jrc_customer_master')
    merge
    expect(choice.reload.contact_id).to eq(base.id)
    expect(Contact.exists?(source.id)).to be(false)
  end

  it 'blocks conflicting include/exclude choices without discarding either person or choice' do
    taxonomy = JrcCustomers::Taxonomy.create!(account: account, kind: 'segment', name: 'TESTE — Conflito')
    JrcCustomers::SegmentOverride.create!(account: account, taxonomy: taxonomy, contact: base, mode: 'include')
    JrcCustomers::SegmentOverride.create!(account: account, taxonomy: taxonomy, contact: source, mode: 'exclude')
    expect { merge }.to raise_error(JrcCustomers::MergePreserver::Conflict)
    expect(JrcCustomers::SegmentOverride.where(taxonomy: taxonomy).count).to eq(2)
    expect(Contact.where(id: [base.id, source.id]).count).to eq(2)
  end

  it 'collapses identical manual choices without duplicating their membership or losing the source audit' do
    taxonomy = JrcCustomers::Taxonomy.create!(account: account, kind: 'segment', name: 'TESTE — Mesma escolha')
    JrcCustomers::SegmentOverride.create!(account: account, taxonomy: taxonomy, contact: base, mode: 'include')
    JrcCustomers::SegmentOverride.create!(account: account, taxonomy: taxonomy, contact: source, mode: 'include')
    source_id = source.id
    merge
    expect(JrcCustomers::SegmentOverride.where(account: account, taxonomy: taxonomy).pluck(:contact_id)).to eq([base.id])
    event = JrcCrm::AuditEvent.find_by!(account: account, resource_type: 'JrcCustomers::Taxonomy', resource_id: taxonomy.id)
    expect(event.metadata['source_contact_id']).to eq(source_id)
  end

  it 'preserves native contact deletion when manual segment choices exist' do
    taxonomy = JrcCustomers::Taxonomy.create!(account: account, kind: 'segment', name: 'TESTE — Pessoa removida')
    choice = JrcCustomers::SegmentOverride.create!(account: account, taxonomy: taxonomy, contact: source, mode: 'include')
    source.destroy!
    expect(JrcCustomers::SegmentOverride.exists?(choice.id)).to be(false)
    expect(taxonomy.reload).to be_persisted
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

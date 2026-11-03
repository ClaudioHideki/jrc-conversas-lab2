require 'rails_helper'

RSpec.describe JrcCustomers::SegmentMembers do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:taxonomy) { JrcCustomers::Taxonomy.create!(account: account, kind: 'segment', name: 'TESTE — Segmento') }
  let(:members) { described_class.new(account: account, actor: actor, taxonomy: taxonomy) }
  let(:writer) { JrcCustomers::TaxonomyWriter.new(account: account, actor: actor) }
  let!(:company) { account.master_companies.create!(name: 'TESTE — Empresa', segment: taxonomy.name, relationship_type: 'customer', size: 'me') }
  let!(:other) { account.master_companies.create!(name: 'TESTE — Outra', relationship_type: 'prospect', size: 'me') }

  before { account.enable_features!('jrc_customer_master') }

  it 'preserves existing classification membership and derives people without copying contacts' do
    person = create(:contact, account: account, company_id: company.id)
    expect(members.companies.pluck(:id)).to eq([company.id])
    expect(members.contacts.pluck(:id)).to eq([person.id])
    expect { members.contacts.to_a }.not_to change(Contact, :count)
  end

  it 'intersects ALL rules and unions ANY rules inside the current scope' do
    taxonomy.update!(selection_mode: 'dynamic', criteria: { match: 'all', rules: [
                       { field: 'relationship_type', operator: 'equal_to', value: 'customer' },
                       { field: 'size', operator: 'equal_to', value: 'me' }
                     ] })
    expect(members.companies.pluck(:id)).to eq([company.id])
    taxonomy.update!(criteria: taxonomy.criteria.merge('match' => 'any'))
    expect(members.companies.pluck(:id)).to contain_exactly(company.id, other.id)
  end

  it 'handles not equal including missing attributes and reevaluates source changes live' do
    taxonomy.update!(selection_mode: 'dynamic', criteria: { match: 'all', rules: [
                       { field: 'size', operator: 'not_equal_to', value: 'large' }
                     ] })
    expect(members.companies.pluck(:id)).to contain_exactly(company.id, other.id)
    other.update!(size: 'large')
    expect(members.companies.pluck(:id)).to eq([company.id])
  end

  it 'matches canonical city and state addresses exactly without substring or foreign-address matches' do
    JrcCustomers::Address.create!(account: account, company: company, address_type: 'business', country: 'BR', city: 'São Paulo', state: 'SP')
    JrcCustomers::Address.create!(account: account, company: other, address_type: 'business', country: 'BR', city: 'São Paulo do Potengi',
                                  state: 'RN')
    taxonomy.update!(selection_mode: 'dynamic', criteria: { match: 'all', rules: [
                       { field: 'city', operator: 'equal_to', value: 'são paulo' }, { field: 'state', operator: 'equal_to', value: 'sp' }
                     ] })
    expect(members.companies.pluck(:id)).to eq([company.id])
  end

  it 'preserves manual choices through criterion changes and supports separate contact overrides' do
    person = create(:contact, account: account)
    writer.override!(taxonomy: taxonomy, kind: 'companies', id: company.id, mode: 'exclude')
    writer.override!(taxonomy: taxonomy, kind: 'companies', id: other.id, mode: 'include')
    choice = writer.override!(taxonomy: taxonomy, kind: 'contacts', id: person.id, mode: 'include')
    taxonomy.update!(selection_mode: 'dynamic', criteria: { match: 'all', rules: [
                       { field: 'active', operator: 'equal_to', value: 'false' }
                     ] })
    expect(members.companies.pluck(:id)).to eq([other.id])
    expect(members.contacts.pluck(:id)).to eq([person.id])
    writer.remove_override!(taxonomy: taxonomy, id: choice.id)
    expect(members.contacts).to be_empty
  end

  it 'never broadens corporate coverage through a stored manual inclusion or negation' do
    issuer = account.master_companies.create!(name: 'TESTE — Operadora restrita', relationship_type: 'internal')
    JrcCrm::BusinessUnit.create!(account: account, company_id: issuer.id, name: 'TESTE — Unidade', code: 'TESTE-SEGMENTOS')
    JrcCustomers::SegmentOverride.create!(account: account, taxonomy: taxonomy, company: issuer, mode: 'include')
    hidden_person = create(:contact, account: account, company_id: issuer.id)
    JrcCustomers::SegmentOverride.create!(account: account, taxonomy: taxonomy, contact: hidden_person, mode: 'include')
    taxonomy.update!(selection_mode: 'dynamic', criteria: { match: 'all', rules: [
                       { field: 'size', operator: 'not_equal_to', value: 'large' }
                     ] })
    expect(members.companies.pluck(:id)).not_to include(issuer.id)
    expect(members.contacts.pluck(:id)).not_to include(hidden_person.id)
    expect(members.overrides).to be_empty
    expect { writer.override!(taxonomy: taxonomy, kind: 'companies', id: issuer.id, mode: 'exclude') }
      .to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'rejects foreign accounts and stale account membership on each new query' do
    foreign = create(:account).master_companies.create!(name: 'TESTE — Outro tenant')
    expect { writer.override!(taxonomy: taxonomy, kind: 'companies', id: foreign.id, mode: 'include') }
      .to raise_error(ActiveRecord::RecordNotFound)
    AccountUser.find_by!(account: account, user: actor).destroy!
    expect { described_class.new(account: account, actor: actor, taxonomy: taxonomy) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'validates the DSL instead of accepting SQL, arbitrary columns, nested rules or unbounded payloads' do
    taxonomy.assign_attributes(selection_mode: 'dynamic', criteria: { match: 'all', rules: [] })
    expect(taxonomy).not_to be_valid
    taxonomy.criteria = { match: 'all', rules: [{ field: 'account_id', operator: 'equal_to', value: account.id.to_s }] }
    expect(taxonomy).not_to be_valid
    taxonomy.criteria = { match: 'all', rules: [{ field: 'name); SELECT 1; --', operator: 'equal_to', value: 'private' }] }
    expect(taxonomy).not_to be_valid
    taxonomy.criteria = { match: 'all', rules: Array.new(21) { { field: 'size', operator: 'equal_to', value: 'me' } } }
    expect(taxonomy).not_to be_valid
  end

  it 'rolls back definition changes if audit persistence fails and rejects a stale revision' do
    revision = taxonomy.updated_at.iso8601(6)
    writer.save!(taxonomy: taxonomy, attributes: { description: 'TESTE — Primeira edição' }, expected_revision: revision)
    expect { writer.save!(taxonomy: taxonomy, attributes: { description: 'Overwrite' }, expected_revision: revision) }
      .to raise_error(JrcCustomers::CompanyWriter::StaleRevision)
    allow(JrcCustomers::Audit).to receive(:record!).and_raise(ActiveRecord::StatementInvalid, 'audit unavailable')
    expect { writer.save!(taxonomy: taxonomy, attributes: { description: 'Rollback' }) }.to raise_error(ActiveRecord::StatementInvalid)
    expect(taxonomy.reload.description).to eq('TESTE — Primeira edição')
  end

  it 'blocks dependency deletion and renaming without rewriting existing companies' do
    expect { writer.destroy!(taxonomy: taxonomy) }.to raise_error(ActiveRecord::RecordInvalid)
    expect { writer.save!(taxonomy: taxonomy, attributes: { name: 'Rename in use' }) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(company.reload.segment).to eq('TESTE — Segmento')
    unused = writer.save!(taxonomy: JrcCustomers::Taxonomy.new(account: account), attributes: { kind: 'segment', name: 'TESTE — Sem uso' })
    writer.destroy!(taxonomy: unused)
    expect(JrcCrm::AuditEvent.where(account: account, resource_id: unused.id, event_type: 'customer_segment_deleted').count).to eq(1)
  end

  it 'keeps ordinary agents read-only and does not grant any module permission from segment usage' do
    agent = create(:user, account: account, role: :agent)
    writer.save!(taxonomy: taxonomy, attributes: { modules: %w[crm backoffice service_desk] })
    before_permissions = AccountUser.find_by!(account: account, user: agent).permissions.sort
    expect(described_class.new(account: account, actor: agent, taxonomy: taxonomy).companies.pluck(:id)).to eq([company.id])
    expect do
      JrcCustomers::TaxonomyWriter.new(account: account, actor: agent).override!(taxonomy: taxonomy, kind: 'companies', id: other.id, mode: 'include')
    end
      .to raise_error(Pundit::NotAuthorizedError)
    expect(AccountUser.find_by!(account: account, user: agent).permissions.sort).to eq(before_permissions)
  end
end

require 'rails_helper'

RSpec.describe JrcCustomers::EconomicGroupWriter do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:writer) { described_class.new(account: account, actor: actor) }
  let(:group) { JrcCustomers::EconomicGroup.create!(account: account, name: 'TESTE — Grupo econômico') }
  let(:company) { account.master_companies.create!(name: 'TESTE — Empresa integrante') }

  before { account.enable_features!('jrc_customer_master', 'jrc_crm') }

  it 'creates an independent audited group without changing native contact labels or companies' do
    label = create(:label, account: account, title: 'vip')
    created = writer.save!(group: JrcCustomers::EconomicGroup.new(account: account),
                           attributes: { name: 'TESTE — Novo conglomerado', description: 'Cadastro corporativo', account_id: 0 })
    expect(created.attributes).to include('account_id' => account.id, 'name' => 'TESTE — Novo conglomerado', 'principal_company_id' => nil)
    expect(created.companies).to be_empty
    expect(label.reload.title).to eq('vip')
    expect(JrcCrm::AuditEvent.where(account: account, resource_id: created.id, event_type: 'customer_economic_group_created').count).to eq(1)
  end

  it 'links an existing company with the native writer, preserves hierarchy and audits the association' do
    parent = account.master_companies.create!(name: 'TESTE — Matriz preservada')
    company.update!(parent_company_id: parent.id)
    original = company.reload.attributes.except('economic_group', 'updated_at', 'updated_by_id', 'customer_code')
    writer.assign!(group: group, company_id: company.id, revision: company.updated_at.iso8601(6))
    expect(company.reload.economic_group).to eq(group.name)
    expect(company.attributes.except('economic_group', 'updated_at', 'updated_by_id', 'customer_code')).to eq(original)
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'customer_economic_group_linked').last.metadata)
      .to eq('company_id' => company.id, 'operation' => 'assign')
  end

  it 'retains legacy strings exactly and registers groups only after saving, not during CSV-style validation' do
    draft = account.master_companies.new(name: 'TESTE — Legado', economic_group: '  Grupo ÁREA  ')
    expect { draft.valid? }.not_to change(JrcCustomers::EconomicGroup, :count)
    draft.save!
    expect(JrcCustomers::EconomicGroup.find_by!(account: account, name: '  Grupo ÁREA  ').companies).to include(draft)
    expect(draft.reload.economic_group).to eq('  Grupo ÁREA  ')
    expect { account.master_companies.create!(name: 'TESTE — Outra', economic_group: 'grupo área') }
      .to change(JrcCustomers::EconomicGroup, :count).by(1)
  end

  it 'requires transfer confirmation and a current company revision' do
    company.update!(economic_group: 'TESTE — Grupo anterior')
    original = company.reload.economic_group
    expect { writer.assign!(group: group, company_id: company.id, revision: company.updated_at.iso8601(6)) }
      .to raise_error(JrcCustomers::MergePreserver::Conflict)
    expect(company.reload.economic_group).to eq(original)
    expect { writer.assign!(group: group, company_id: company.id, revision: 'stale', confirm_transfer: true) }
      .to raise_error(JrcCustomers::CompanyWriter::StaleRevision)
    writer.assign!(group: group, company_id: company.id, revision: company.updated_at.iso8601(6), confirm_transfer: true)
    expect(company.reload.economic_group).to eq(group.name)
  end

  it 'supports an optional principal only after membership and blocks unlinking or deleting that company' do
    expect { writer.save!(group: group, attributes: { principal_company_id: company.id }) }.to raise_error(ActiveRecord::RecordInvalid)
    writer.assign!(group: group, company_id: company.id, revision: company.updated_at.iso8601(6))
    writer.save!(group: group, attributes: { principal_company_id: company.id })
    expect(group.reload.principal_company_id).to eq(company.id)
    expect { writer.assign!(group: group, company_id: company.id, revision: company.reload.updated_at.iso8601(6), remove: true) }
      .to raise_error(ActiveRecord::RecordInvalid)
    expect { Company.transaction(requires_new: true) { Companies::DeleteJob.perform_now(company_id: company.id) } }
      .to raise_error(ActiveRecord::InvalidForeignKey)
    expect(company.reload.economic_group).to eq(group.name)
  end

  it 'clears the principal explicitly before unlinking, retaining both company and the group history' do
    writer.assign!(group: group, company_id: company.id, revision: company.updated_at.iso8601(6))
    writer.save!(group: group, attributes: { principal_company_id: company.id })
    writer.save!(group: group, attributes: { principal_company_id: nil })
    writer.assign!(group: group, company_id: company.id, revision: company.reload.updated_at.iso8601(6), remove: true)
    expect(company.reload.economic_group).to be_nil
    expect(group.reload.principal_company_id).to be_nil
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'customer_economic_group_linked').count).to eq(2)
  end

  it 'preserves assigned names and saved criteria but accepts a description edit after a refused rename' do
    company.update!(economic_group: group.name)
    expect { writer.save!(group: group, attributes: { name: 'TESTE — Novo nome' }) }.to raise_error(ActiveRecord::RecordInvalid)
    writer.save!(group: group, attributes: { description: 'Atualização permitida' })
    expect(group.reload.attributes).to include('name' => 'TESTE — Grupo econômico', 'description' => 'Atualização permitida')
    company.update!(economic_group: nil)
    JrcCustomers::Taxonomy.create!(account: account, kind: 'segment', name: 'TESTE — Critério preservado', selection_mode: 'dynamic',
                                   criteria: { match: 'all', rules: [{ field: 'economic_group', operator: 'equal_to', value: group.name }] })
    expect { writer.destroy!(group: group, expected_revision: group.updated_at.iso8601(6)) }.to raise_error(ActiveRecord::RecordInvalid)
    expect { writer.save!(group: group, attributes: { name: 'TESTE — Nome novo' }) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'rolls back both the native company write and its association audit on an audit failure' do
    group
    company
    original = company.reload.attributes
    allow(JrcCustomers::Audit).to receive(:record!).and_call_original
    allow(JrcCustomers::Audit).to receive(:record!).with(hash_including(event_type: 'customer_economic_group_linked'))
                                                   .and_raise(ActiveRecord::RecordInvalid)
    expect { writer.assign!(group: group, company_id: company.id, revision: company.updated_at.iso8601(6)) }
      .to raise_error(ActiveRecord::RecordInvalid)
    expect(company.reload.attributes).to eq(original)
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'customer_company_updated')).to be_empty
  end

  it 'deletes only an unused group with a matching revision and preserves its audit' do
    group
    expect { writer.destroy!(group: group, expected_revision: 'stale') }.to raise_error(JrcCustomers::CompanyWriter::StaleRevision)
    writer.destroy!(group: group, expected_revision: group.updated_at.iso8601(6))
    expect(JrcCustomers::EconomicGroup.exists?(group.id)).to be(false)
    expect(JrcCrm::AuditEvent.where(account: account, resource_id: group.id, event_type: 'customer_economic_group_deleted').count).to eq(1)
  end

  it 'enforces the principal account boundary in PostgreSQL even when application validation is bypassed' do
    foreign = create(:company)
    group
    expect do
      JrcCustomers::EconomicGroup.transaction(requires_new: true) do
        sql = "UPDATE jrc_customer_economic_groups SET principal_company_id = #{foreign.id.to_i} WHERE id = #{group.id.to_i}"
        ActiveRecord::Base.connection.execute(sql)
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(group.reload.principal_company_id).to be_nil
  end
end

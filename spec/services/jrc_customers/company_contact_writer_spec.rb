require 'rails_helper'

RSpec.describe JrcCustomers::CompanyContactWriter do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :agent) }
  let(:company) { account.master_companies.create!(name: 'TESTE SINTÉTICO — Empresa do vínculo') }
  let(:contact) { create(:contact, account: account, company_id: company.id) }
  let(:writer) { described_class.new(account: account, actor: actor) }

  before { account.enable_features!('jrc_customer_master') }

  it 'saves the role and primary on the existing person with audit and ignores caller ownership attributes' do
    writer.update!(id: contact.id, attributes: { company_role: 'finance', company_primary: true, account_id: 0, user_id: 0 })
    expect(contact.reload.attributes.slice('account_id', 'company_id', 'company_role', 'company_primary'))
      .to eq('account_id' => account.id, 'company_id' => company.id, 'company_role' => 'finance', 'company_primary' => true)
    event = JrcCrm::AuditEvent.find_by!(
      account: account, resource_type: 'Contact', resource_id: contact.id,
      event_type: 'customer_contact_primary_changed'
    )
    expect(event.actor_id).to eq(actor.id)
    expect(event.to_value.slice('company_role', 'company_primary')).to eq('company_role' => 'finance', 'company_primary' => true)
  end

  it 'requires explicit confirmation and atomically replaces the previous primary with an audit for both people' do
    previous = create(:contact, account: account, company_id: company.id, company_primary: true)
    expect { writer.update!(id: contact.id, attributes: { company_primary: true }) }
      .to raise_error(JrcCustomers::MergePreserver::Conflict)
    expect(previous.reload.company_primary?).to be(true)
    writer.update!(id: contact.id, attributes: { company_primary: true }, confirm_primary_change: true)
    expect(account.contacts.where(company_id: company.id, company_primary: true).pluck(:id)).to eq([contact.id])
    expect(previous.reload.company_primary?).to be(false)
    events = JrcCrm::AuditEvent.where(account: account, event_type: 'customer_contact_primary_changed')
    expect(events.pluck(:resource_id)).to contain_exactly(contact.id, previous.id)
    expect(account.contacts.where(id: [contact.id, previous.id]).count).to eq(2)
  end

  it 'rolls back both people when native audit persistence fails' do
    previous = create(:contact, account: account, company_id: company.id, company_primary: true)
    allow(JrcCustomers::Audit).to receive(:record!).and_raise(ActiveRecord::RecordInvalid)
    expect { writer.update!(id: contact.id, attributes: { company_primary: true }, confirm_primary_change: true) }
      .to raise_error(ActiveRecord::RecordInvalid)
    expect(previous.reload.company_primary?).to be(true)
    expect(contact.reload.company_primary?).to be(false)
  end

  it 'preserves historical context but clears the old company fields on transfer and detach without deleting the person' do
    contact.update!(job_title: 'Financeiro', department: 'Contas', company_role: 'finance', company_primary: true)
    destination = account.master_companies.create!(name: 'TESTE SINTÉTICO — Destino')
    expect { writer.update!(id: contact.id, attributes: { company_id: destination.id }) }
      .to raise_error(JrcCustomers::MergePreserver::Conflict)
    writer.update!(id: contact.id, attributes: { company_id: destination.id }, confirm_reassignment: true)
    expect(contact.reload.attributes.slice('job_title', 'department', 'company_role', 'company_primary'))
      .to eq('job_title' => nil, 'department' => nil, 'company_role' => nil, 'company_primary' => false)
    event = JrcCrm::AuditEvent.find_by!(account: account, resource_id: contact.id, event_type: 'customer_contact_linked')
    expect(event.from_value.slice('company_id', 'company_role')).to eq('company_id' => company.id, 'company_role' => 'finance')
    writer.update!(id: contact.id, attributes: { company_id: nil }, confirm_reassignment: true)
    expect(account.contacts.find(contact.id).company_id).to be_nil
  end

  it 'rejects invalid roles, inactive primaries, primaries without a company, and foreign contacts or companies' do
    expect { writer.update!(id: contact.id, attributes: { company_role: 'owner_grant' }) }.to raise_error(ActiveRecord::RecordInvalid)
    expect { writer.update!(id: contact.id, attributes: { company_primary: true, company_contact_status: 'inactive' }) }
      .to raise_error(ActiveRecord::RecordInvalid)
    unlinked = create(:contact, account: account)
    expect { writer.update!(id: unlinked.id, attributes: { company_primary: true }) }.to raise_error(ActiveRecord::RecordInvalid)
    foreign_account = create(:account)
    foreign_company = foreign_account.master_companies.create!(name: 'TESTE SINTÉTICO — Outra conta')
    foreign = create(:contact, account: foreign_account, company_id: foreign_company.id)
    expect { writer.update!(id: foreign.id, attributes: { company_primary: true }) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { writer.update!(id: contact.id, attributes: { company_id: foreign.company_id }, confirm_reassignment: true) }
      .to raise_error(ActiveRecord::RecordInvalid)
    expect(contact.reload.company_id).to eq(company.id)
  end

  it 'revalidates a withdrawn directory permission on every write' do
    actor
    role = create(:custom_role, account: account, permissions: %w[contact_manage])
    member = account.account_users.find_by!(user: actor)
    member.update!(custom_role: role)
    writer.update!(id: contact.id, attributes: { company_role: 'technical' })
    role.update!(permissions: %w[jrc_crm])
    expect { writer.update!(id: contact.id, attributes: { company_primary: true }) }.to raise_error(Pundit::NotAuthorizedError)
    expect(contact.reload.company_primary?).to be(false)
  end

  it 'enforces one active primary at the database boundary even when a legacy caller bypasses validations' do
    create(:contact, account: account, company_id: company.id, company_primary: true)
    expect do
      Contact.transaction(requires_new: true) do
        Contact.connection.execute("UPDATE contacts SET company_primary = TRUE WHERE id = #{Integer(contact.id)}")
      end
    end.to raise_error(ActiveRecord::RecordNotUnique)
    unlinked = create(:contact, account: account)
    expect do
      Contact.transaction(requires_new: true) do
        Contact.connection.execute("UPDATE contacts SET company_primary = TRUE WHERE id = #{Integer(unlinked.id)}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid)
  end

  it 'refuses a destructive migration rollback after a company context has been recorded' do
    contact.update!(company_role: 'finance')
    require Rails.root.join('db/migrate/20261103090000_add_company_contact_context_to_contacts')
    expect { AddCompanyContactContextToContacts.new.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    expect(contact.reload.company_role).to eq('finance')
    expect(ActiveRecord::Base.connection.indexes(:contacts).any? { |index| index.name == 'contacts_one_primary_per_company' }).to be(true)
  end
end

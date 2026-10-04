require 'rails_helper'

RSpec.describe JrcCustomers::Company do
  let(:account) { create(:account) }
  let(:other) { create(:account) }
  let(:company) { described_class.create!(account: account, name: 'Master A', tax_id: '11222333000181') }

  it 'reuses the original companies table and stable IDs' do
    expect(described_class.table_name).to eq('companies')
    expect(company.id).to be_a(Integer)
    company.update!(relationship_type: 'customer')
    expect(company.reload.tax_id).to eq('11222333000181')
  end
  it 'prevents normalized fiscal duplicates inside one account' do
    company
    duplicate = described_class.new(account: account, name: 'Duplicate', tax_id: '11.222.333/0001-81')
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:tax_id]).not_to be_empty
  end
  it 'allows the same fiscal document in another tenant' do
    company
    expect(described_class.new(account: other, name: 'Other', tax_id: '11222333000181')).to be_valid
  end
  it 'supports the alphanumeric CNPJ format' do
    expect(described_class.new(account: account, name: 'Alphanumeric', tax_id: '12ABC34501DE35')).to be_valid
  end
  it 'rejects a foreign parent company' do
    foreign = described_class.create!(account: other, name: 'Foreign')
    company.parent_company_id = foreign.id
    expect(company).not_to be_valid
  end
  it 'prevents parent cycles' do
    child = described_class.create!(account: account, name: 'Branch', parent_company: company)
    company.parent_company_id = child.id
    expect(company).not_to be_valid
  end

  it 'supports a primary relationship with separate secondary classifications and tags' do
    company.relationship_type = 'customer'
    company.relationship_tags = %w[partner supplier]
    company.tags = ['VIP', 'Strategic']
    expect(company).to be_valid
    company.relationship_tags << 'customer'
    expect(company).not_to be_valid
    expect(company.errors[:relationship_tags]).not_to be_empty
  end
  it 'rejects a responsible user outside the account' do
    company.owner = create(:user, account: other)
    expect(company).not_to be_valid
  end
  it 'rejects a cross-tenant contact link at the model layer' do
    other.enable_features!('jrc_customer_master')
    contact = create(:contact, account: other)
    contact.company_id = company.id
    expect(contact).not_to be_valid
  end
  it 'rejects a cross-tenant contact link at the database layer' do
    contact = create(:contact, account: other)
    expect { Contact.transaction(requires_new: true) { contact.update_column(:company_id, company.id) } }
      .to raise_error(ActiveRecord::InvalidForeignKey)
  end
  it 'creates supplemental points on the same Contact without new ContactInbox rows' do
    contact = create(:contact, account: account)
    expect do
      JrcCustomers::ContactPoint.create!(account: account, contact: contact, kind: 'corporate_email', value: 'ANA@EXAMPLE.TEST')
    end.not_to change(ContactInbox, :count)
    expect(contact.contact_points.first.normalized_value).to eq('ana@example.test')
  end
  it 'rejects a contact point crossing tenant boundaries' do
    point = JrcCustomers::ContactPoint.new(account: account, contact: create(:contact, account: other), kind: 'extension', value: '1596')
    expect(point).not_to be_valid
  end
end

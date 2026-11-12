require 'rails_helper'

RSpec.describe JrcCustomers::CompanyImport do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:operator_a) { account.master_companies.create!(name: 'Synthetic operator A', relationship_type: 'internal') }
  let(:operator_b) do
    account.master_companies.create!(name: 'Synthetic hidden operator B', relationship_type: 'internal', tax_id: '11222333000181')
  end
  let(:unit_a) { account.jrc_crm_business_units.create!(name: 'Synthetic A', code: SecureRandom.hex(8), company_id: operator_a.id) }
  let(:unit_b) { account.jrc_crm_business_units.create!(name: 'Synthetic B', code: SecureRandom.hex(8), company_id: operator_b.id) }
  let(:grant) do
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: operator_a, business_unit: unit_a,
                                                active: true, structure_managed: true)
  end
  let(:customer) { account.master_companies.create!(name: 'Synthetic external customer', relationship_type: 'prospect') }
  let(:writer) { JrcCustomers::CompanyWriter.new(account: account, actor: actor) }
  let(:content) { "id,name\n#{operator_b.id},Synthetic unauthorized change\n" }
  let(:importer) { described_class.new(account: account, actor: actor, content: content) }

  before do
    account.enable_features!('jrc_crm', 'jrc_customer_master')
    actor
    unit_a
    unit_b
    grant
  end

  it 'rejects an uncovered internal company in preview without returning its identity or revision' do
    preview = importer.preview
    expect([preview[:token], preview[:rows]]).to eq([nil, []])
    expect(preview[:errors]).to contain_exactly(include(line: 2, error: 'Company unavailable in the current scope'))
    expect(preview.to_json).not_to include(operator_b.name, operator_b.updated_at.iso8601(6))
    expect(operator_b.reload.name).to eq('Synthetic hidden operator B')
  end

  it 'also rejects a hidden company resolved by fiscal identity instead of the supplied id' do
    csv = "name,tax_id\nSynthetic unauthorized fiscal match,#{operator_b.tax_id}\n"
    preview = described_class.new(account: account, actor: actor, content: csv).preview
    expect([preview[:token], preview[:rows], preview[:errors].length]).to eq([nil, [], 1])
    expect(preview[:errors].first[:error]).to eq('Company unavailable in the current scope')
    expect(operator_b.reload.name).to eq('Synthetic hidden operator B')
  end

  it 'rejects the direct writer even when changing an inaccessible operator into an external company' do
    original = operator_b.attributes.slice('name', 'relationship_type', 'updated_at')
    expect do
      writer.save!(company: operator_b, attributes: { name: 'Unauthorized writer', relationship_type: 'customer' })
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(operator_b.reload.attributes.slice(*original.keys)).to eq(original)
  end

  it 'preserves an authorized internal company update for a limited administrator' do
    writer.save!(company: operator_a, attributes: { name: 'Synthetic authorized issuer revision' })
    expect(operator_a.reload.name).to eq('Synthetic authorized issuer revision')
    expect(operator_a.updated_by_id).to eq(actor.id)
    expect(operator_b.reload.name).to eq('Synthetic hidden operator B')
  end

  it 'preserves canonical external customer creation and promotion used by CRM' do
    writer.save!(company: customer, attributes: { relationship_type: 'customer' })
    created = writer.save!(company: account.master_companies.new, attributes: { name: 'Synthetic new external', relationship_type: 'prospect' })
    expect(customer.reload.relationship_type).to eq('customer')
    expect(created).to have_attributes(account_id: account.id, relationship_type: 'prospect', created_by_id: actor.id)
  end

  it 'does not grant a limited administrator a new internal operator through the writer or CSV' do
    target = account.master_companies.new
    expect do
      writer.save!(company: target, attributes: { name: 'Synthetic unscoped new operator', relationship_type: 'internal' })
    end.to raise_error(ActiveRecord::RecordNotFound)
    csv = "name,relationship_type\nSynthetic unscoped CSV operator,internal\n"
    preview = described_class.new(account: account, actor: actor, content: csv).preview
    expect([preview[:token], preview[:rows], preview[:errors].length]).to eq([nil, [], 1])
    expect(account.master_companies.where(name: [target.name, 'Synthetic unscoped CSV operator'])).to be_empty
  end

  it 'rejects changing an external customer into an ungranted internal operator' do
    expect do
      writer.save!(company: customer, attributes: { relationship_type: 'internal' })
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(customer.reload.relationship_type).to eq('prospect')
    expect(account.jrc_crm_user_business_units.where(user: actor).pluck(:scope)).to eq(['BUSINESS_UNIT'])
  end

  it 'rejects an uncovered parent link without changing the external customer' do
    expect do
      writer.save!(company: customer, attributes: { parent_company_id: operator_b.id })
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(customer.reload.parent_company_id).to be_nil
    csv = "id,name,parent_company_id\n#{customer.id},Synthetic external customer,#{operator_b.id}\n"
    preview = described_class.new(account: account, actor: actor, content: csv).preview
    expect([preview[:token], preview[:rows], preview[:errors].length]).to eq([nil, [], 1])
  end

  it 'rechecks coverage after preview rather than treating its signed token as an authorization grant' do
    group = account.jrc_crm_user_business_units.create!(user: actor, scope: 'GROUP', active: true, structure_managed: true)
    preview = importer.preview
    expect(preview[:token]).to be_present
    group.update!(active: false)
    expect { importer.apply!(token: preview[:token]) }.to raise_error(JrcCustomers::CompanyImport::InvalidImport)
    expect(operator_b.reload.name).to eq('Synthetic hidden operator B')
  end

  it 'preserves a legitimate group-authorized CSV update using the same native company and writer' do
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'GROUP', active: true, structure_managed: true)
    preview = importer.preview
    expect(preview[:errors]).to be_empty
    expect(importer.apply!(token: preview[:token])).to include(applied: 1, company_ids: [operator_b.id])
    expect(operator_b.reload.name).to eq('Synthetic unauthorized change')
    expect(operator_b.relationship_type).to eq('internal')
  end

  it 'preserves initial issuer setup before an account has configured corporate units' do
    bootstrap = create(:account)
    administrator = create(:user, account: bootstrap, role: :administrator)
    target = bootstrap.master_companies.new
    JrcCustomers::CompanyWriter.new(account: bootstrap, actor: administrator).save!(
      company: target, attributes: { name: 'Synthetic bootstrap issuer', relationship_type: 'internal' }
    )
    expect(target).to have_attributes(account_id: bootstrap.id, relationship_type: 'internal', created_by_id: administrator.id)
  end

  it 'does not let group coverage cross an account boundary' do
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'GROUP', active: true, structure_managed: true)
    foreign = create(:account).master_companies.create!(name: 'Synthetic foreign company')
    expect { writer.save!(company: foreign, attributes: { name: 'Foreign overwrite' }) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(foreign.reload.name).to eq('Synthetic foreign company')
  end

  it 'imports native establishment metadata through the scoped, reviewed company writer' do
    csv = "id,name,tax_id,store_code,cluster,establishment_phones\n" \
          "#{customer.id},Synthetic external customer,11444777000161,SYNTHETIC-01,Synthetic cluster,+5511999991234\n"
    operation = described_class.new(account: account, actor: actor, content: csv)
    preview = operation.preview
    expect(preview[:errors]).to be_empty
    expect(preview[:token]).to be_present
    expect(JrcCustomers::EstablishmentMetadata.read(customer.reload)).to eq({})

    expect(operation.apply!(token: preview[:token])).to include(applied: 1, company_ids: [customer.id])
    expect(JrcCustomers::EstablishmentMetadata.read(customer.reload)).to include(
      'store_code' => 'SYNTHETIC-01', 'cluster' => 'Synthetic cluster', 'phones' => ['+5511999991234']
    )
    expect(customer.updated_by_id).to eq(actor.id)
  end

  it 'does not let establishment columns bypass operator coverage or mint a preview grant' do
    csv = "id,name,tax_id,store_code,cluster\n" \
          "#{operator_b.id},Synthetic hidden operator B,11222333000181,SYNTHETIC-HIDDEN,Synthetic cluster\n"
    preview = described_class.new(account: account, actor: actor, content: csv).preview
    expect(preview[:token]).to be_nil
    expect(preview[:rows]).to be_empty
    expect(preview[:errors]).to contain_exactly(include(line: 2, error: 'Company unavailable in the current scope'))
    expect(JrcCustomers::EstablishmentMetadata.read(operator_b.reload)).to eq({})
  end
end

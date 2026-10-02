require 'rails_helper'

RSpec.describe 'Customer master service contracts' do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:company) { account.master_companies.create!(name: 'Master company') }
  before { account.enable_features!('jrc_customer_master', 'jrc_crm') }

  it 'does not create a person when merely validating a CRM lead' do
    lead = JrcCrm::Lead.new(account: account, owner: actor, name: 'Lead', email: 'lead@example.test', company: company)
    expect { lead.valid? }.not_to change(Contact, :count)
    expect(lead.contact).to be_new_record
  end
  it 'creates and links the person atomically on lead save' do
    lead = JrcCrm::Lead.create!(account: account, owner: actor, name: 'Lead', email: 'lead@example.test', company: company)
    expect(lead.contact_id).to be_present
    expect(lead.contact.reload.company_id).to eq(company.id)
  end
  it 'rolls back a failed lead without orphan persons' do
    lead = JrcCrm::Lead.new(account: account, owner: actor, name: nil, email: 'invalidlead@example.test', company: company)
    expect { expect { lead.save! }.to raise_error(ActiveRecord::RecordInvalid) }.not_to change(Contact, :count)
  end
  it 'does not change contact company to resolve a conflicting CRM choice' do
    first = create(:contact, account: account, company_id: company.id)
    other = account.master_companies.create!(name: 'Other company')
    lead = JrcCrm::Lead.new(account: account, owner: actor, name: 'Lead', contact: first, company: other)
    expect(lead).not_to be_valid
    expect(first.reload.company_id).to eq(company.id)
  end
  it 'finds a unique alternate telephone without changing any source identifier' do
    contact = create(:contact, account: account)
    contact.contact_points.create!(account: account, kind: 'whatsapp', value: '+5511999999999')
    expect(JrcCustomers::IdentityResolver.new(account: account).call(phone: '+55 11 99999-9999').pluck(:id)).to eq([contact.id])
  end
  it 'reports shared numbers as ambiguous rather than arbitrarily choosing a person' do
    contacts = 2.times.map { create(:contact, account: account) }
    contacts.each { |contact| contact.contact_points.create!(account: account, kind: 'phone', value: '+551133334444') }
    expect(JrcCustomers::IdentityResolver.new(account: account).call(phone: '+551133334444').pluck(:id)).to match_array(contacts.map(&:id))
  end
  it 'does not match contacts in another tenant' do
    foreign = create(:account)
    create(:contact, account: foreign, email: 'foreign@example.test')
    expect(JrcCustomers::IdentityResolver.new(account: account).call(email: 'foreign@example.test')).to be_empty
  end
  it 'requires review instead of linking companies based only on similar names' do
    account.disable_features!('jrc_customer_master')
    company
    legacy = account.jrc_crm_organizations.create!(name: company.name)
    mapper = JrcCustomers::LegacyCompanyMapper.new(account: account, organization: legacy)
    expect { mapper.plan }.to raise_error(JrcCustomers::LegacyCompanyMapper::Conflict)
    expect(legacy.reload.company_id).to be_nil
  end
  it 'maps a reviewed legacy ID idempotently without deleting the legacy record' do
    account.disable_features!('jrc_customer_master')
    legacy = account.jrc_crm_organizations.create!(name: 'Legacy')
    mapper = JrcCustomers::LegacyCompanyMapper.new(account: account, organization: legacy, target_company_id: company.id)
    expect { mapper.plan }.not_to change(JrcCustomers::Company, :count)
    expect(mapper.apply!.id).to eq(company.id)
    expect(mapper.apply!.id).to eq(company.id)
    expect(legacy.reload.company_id).to eq(company.id)
  end
  it 'refuses stale company edits before persisting or writing an audit' do
    stamp = company.updated_at.iso8601(6)
    company.update!(updated_at: company.updated_at + 1.second)
    writer = JrcCustomers::CompanyWriter.new(account: account, actor: actor)
    expect { writer.save!(company: company, attributes: { name: 'Stale overwrite' }, expected_revision: stamp) }
      .to raise_error(JrcCustomers::CompanyWriter::StaleRevision)
    expect(company.reload.name).to eq('Master company')
  end
  it 'does not assign a commercial customer relationship to a technical contact' do
    contact = create(:contact, account: account)
    expect(contact.registration_status).to eq('provisional')
    expect(contact.company_id).to be_nil
  end
  it 'keeps unfiltered campaign scope unchanged' do
    scope = account.contacts.where(blocked: false)
    expect(JrcCustomers::CampaignFilter.apply(scope: scope, account: account, filters: {})).to equal(scope)
  end
  it 'filters the existing Contact scope by company segment and department' do
    company.update!(segment: 'Health', relationship_type: 'customer')
    first = create(:contact, account: account, company_id: company.id, department: 'Finance')
    create(:contact, account: account, company_id: company.id, department: 'Sales')
    result = JrcCustomers::CampaignFilter.apply(scope: account.contacts, account: account, filters: { segment: 'Health', department: 'Finance' })
    expect(result.pluck(:id)).to eq([first.id])
  end
end

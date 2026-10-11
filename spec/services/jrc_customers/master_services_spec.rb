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
  it 'finds account-wide duplicate candidates across primary and alternate identities without self-duplicates' do
    first = create(:contact, account: account, email: 'shared@example.test')
    second = create(:contact, account: account)
    second.contact_points.create!(account: account, kind: 'corporate_email', value: 'SHARED@example.test')
    first.contact_points.create!(account: account, kind: 'email', value: first.email)
    alone = create(:contact, account: account, email: 'alone@example.test')
    alone.contact_points.create!(account: account, kind: 'alternate_email', value: alone.email)
    create(:contact, account: create(:account), email: first.email)
    result = JrcCustomers::IdentityResolver.new(account: account).duplicates
    expect(result.pluck(:id)).to match_array([first.id, second.id])
    expect(Contact.where(id: [first.id, second.id]).count).to eq(2)
  end
  it 'groups telephone channels as one identity' do
    first, second = 2.times.map { create(:contact, account: account) }
    first.contact_points.create!(account: account, kind: 'phone', value: '+551133334444')
    second.contact_points.create!(account: account, kind: 'whatsapp', value: '+55 11 3333-4444')
    expect(JrcCustomers::IdentityResolver.new(account: account).duplicates.pluck(:id)).to match_array([first.id, second.id])
  end
  it 'does not mark an identity shared only with another tenant as duplicated' do
    contact = create(:contact, account: account, email: 'tenant@example.test')
    create(:contact, account: create(:account), email: contact.email)
    expect(JrcCustomers::IdentityResolver.new(account: account).duplicates).to be_empty
  end
  it 'filters unassigned contacts by canonical company owner while preserving the supplied contact scope' do
    without_company = create(:contact, account: account)
    without_owner = create(:contact, account: account, company_id: company.id)
    owned = account.master_companies.create!(name: 'Owned', owner_id: actor.id)
    create(:contact, account: account, company_id: owned.id)
    result = JrcCustomers::ContactQuery.new(account: account, scope: account.contacts, query: nil, view: 'unassigned').call
    expect(result.pluck(:id)).to match_array([without_company.id, without_owner.id])
    limited = JrcCustomers::ContactQuery.new(account: account, scope: account.contacts.where(id: without_owner.id), query: nil, view: 'unassigned').call
    expect(limited.pluck(:id)).to eq([without_owner.id])
  end
  it 'rejects unsupported directory views and keeps canonical persons intact' do
    contact = create(:contact, account: account, company_id: company.id)
    result = JrcCustomers::ContactQuery.new(account: account, scope: account.contacts, query: nil, view: 'people').call
    expect(result.pluck(:id)).to eq([contact.id])
    expect { JrcCustomers::ContactQuery.new(account: account, scope: account.contacts, query: nil, view: 'invalid') }
      .to raise_error(ActionController::BadRequest)
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

  it 'assigns a stable automatic company code and visible audit actors through the writer' do
    record = account.master_companies.new(name: 'Coded company')
    writer = JrcCustomers::CompanyWriter.new(account: account, actor: actor)
    writer.save!(company: record, attributes: { relationship_type: 'prospect' })
    expect(record.customer_code).to eq(format('EMP-%06d', record.id))
    expect(record.created_by_id).to eq(actor.id)
    expect(record.updated_by_id).to eq(actor.id)
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
    JrcCustomers::Taxonomy.create!(account: account, kind: 'segment', name: 'Health')
    company.update!(segment: 'Health', relationship_type: 'customer')
    first = create(:contact, account: account, company_id: company.id, department: 'Finance')
    create(:contact, account: account, company_id: company.id, department: 'Sales')
    result = JrcCustomers::CampaignFilter.apply(scope: account.contacts, account: account, filters: { segment: 'Health', department: 'Finance' })
    expect(result.pluck(:id)).to eq([first.id])
  end
end

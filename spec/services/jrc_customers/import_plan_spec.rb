require 'rails_helper'

RSpec.describe JrcCustomers::ImportPlan do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:kind) { 'contacts' }
  let(:csv) { "name,email\nPerson,person@example.test\n" }
  let(:file) { JrcCustomers::ImportFile.new(content: csv, kind: kind) }
  let(:mapping) { file.metadata.fetch(:suggested_mapping) }
  let(:options) { { existing: 'update', confirmations: {} } }
  let(:plan) { described_class.new(account: account, actor: actor, file: file, mapping: mapping, options: options).call }

  before { account.enable_features!('jrc_customer_master') }

  it 'validates new contacts without writing contacts, companies, audits or queued events' do
    actor
    before = [account.contacts.count, account.master_companies.count, JrcCrm::AuditEvent.count, enqueued_jobs.size]
    expect(plan.errors).to be_empty
    expect(plan.rows.first).to include(entity: 'contact', action: 'create', record_id: nil)
    expect([account.contacts.count, account.master_companies.count, JrcCrm::AuditEvent.count, enqueued_jobs.size]).to eq(before)
  end

  it 'matches the native normalized identities and warns about the reviewed update without saving during preview' do
    contact = create(:contact, account: account, email: 'person@example.test', name: 'Original')
    before = contact.reload.attributes
    csv.replace("name,email\nChanged, PERSON@EXAMPLE.TEST \n")
    expect(plan.errors).to be_empty
    expect(plan.rows.first).to include(action: 'update', record_id: contact.id, revision: contact.updated_at.iso8601(6),
                                       warnings: ['EXISTING_CONTACT'])
    expect(contact.reload.attributes).to eq(before)
  end

  it 'rejects an ID and an email that refer to different people without choosing or merging either record' do
    first = create(:contact, account: account)
    second = create(:contact, account: account, email: 'second@example.test')
    csv.replace("id,email,name\n#{first.id},#{second.email},Changed\n")
    expect(plan.errors.first).to include(line: 2, field: 'identity', code: 'AMBIGUOUS_CONTACT')
    expect(plan.rows).to be_empty
    expect(account.contacts.count).to eq(2)
  end

  it 'reports repeated normalized identities in the same file instead of silently discarding a row' do
    csv << "Second, PERSON@EXAMPLE.TEST \n"
    expect(plan.errors).to include(hash_including(line: 3, code: 'REPEATED_CONTACT'))
    expect(plan.totals).to include('total_rows' => 2, 'valid_rows' => 1, 'invalid_rows' => 1)
  end

  it 'ignores nonidentity values for an explicitly skipped existing contact without clearing its fields' do
    contact = create(:contact, account: account, email: 'person@example.test')
    before = contact.reload.attributes
    csv.replace("email,name,company_primary,labels,company_id\nperson@example.test,Changed,invalid,unknown,invalid\n")
    options[:existing] = 'skip'
    expect(plan.errors).to be_empty
    expect(plan.rows.first).to include(action: 'skip', record_id: contact.id, attributes: {})
    expect(contact.reload.attributes).to eq(before)
  end

  it 'requires the same reassignment confirmation as the canonical contact writer' do
    first = account.master_companies.create!(name: 'Original')
    second = account.master_companies.create!(name: 'Destination')
    contact = create(:contact, account: account, company_id: first.id, job_title: 'Old title', department: 'Old department', company_role: 'finance')
    csv.replace("id,name,company_id\n#{contact.id},Updated,#{second.id}\n")
    expect(plan.errors).to include(hash_including(field: 'company_id', code: 'CONFIRM_REASSIGNMENT'))
    expect(contact.reload.company_id).to eq(first.id)
  end

  it 'previews the real context reset after an explicitly confirmed company transfer' do
    first = account.master_companies.create!(name: 'Original')
    second = account.master_companies.create!(name: 'Destination')
    contact = create(:contact, account: account, company_id: first.id, job_title: 'Old title', company_role: 'finance')
    csv.replace("id,company_id,job_title,company_role\n#{contact.id},#{second.id},New title,technical\n")
    options[:confirmations] = { 'reassignment' => true }
    expect(plan.errors).to be_empty
    expect(plan.rows.first[:attributes]).to include('company_id' => second.id, 'job_title' => nil, 'company_role' => nil)
    expect(contact.reload.job_title).to eq('Old title')
  end

  it 'requires explicit primary replacement of an existing principal' do
    company = account.master_companies.create!(name: 'Linked')
    create(:contact, account: account, company_id: company.id, company_primary: true)
    csv.replace("name,email,company_id,company_primary\nNew,new@example.test,#{company.id},true\n")
    expect(plan.errors).to include(hash_including(code: 'CONFIRM_PRIMARY_CHANGE'))
  end

  it 'validates private fiscal identities without returning their raw values or granting signing powers' do
    csv.replace("name,email,personal_tax_identifier\nPerson,person@example.test,11144477735\n")
    expect(plan.errors).to be_empty
    expect(plan.rows.first[:personal_identifier]).to eq('11144477735')
    expect(plan.rows.first[:identity_revision]).to eq(0)
    expect(plan.public_rows.to_json).not_to include('11144477735', 'signing_authority')
    expect(JrcCustomers::SigningIdentity.where(account: account)).to be_empty
  end

  it 'reports invalid personal identifiers by line and field' do
    csv.replace("name,personal_tax_identifier\nPerson,invalid\n")
    expect(plan.errors).to include(hash_including(line: 2, field: 'personal_tax_identifier'))
  end

  it 'denies another account contact and does not treat a supplied ID as a grant' do
    other = create(:contact)
    csv.replace("id,name\n#{other.id},Changed\n")
    expect(plan.errors).to include(hash_including(line: 2, code: 'UNAVAILABLE_CONTACT'))
    expect(other.reload.name).not_to eq('Changed')
  end

  it 'changes the review digest when an existing record changes and canonicalizes reordered JSON mappings' do
    contact = create(:contact, account: account, email: 'person@example.test')
    original = plan.digest
    reordered = described_class.new(account: account, actor: actor, file: file, mapping: mapping.to_a.reverse.to_h, options: options).call
    expect(reordered.digest).to eq(original)
    contact.update!(name: 'Changed after preview')
    refreshed = described_class.new(account: account, actor: actor, file: file, mapping: mapping, options: options).call
    expect(refreshed.digest).not_to eq(original)
  end

  it 'refuses unsupported existing-record handling and truthy strings used as confirmations' do
    options[:existing] = 'merge'
    expect { plan }.to raise_error(JrcCustomers::ImportFile::InvalidFile)
    options[:existing] = 'update'
    options[:confirmations] = { 'reassignment' => 'false' }
    expect { plan }.to raise_error(JrcCustomers::ImportFile::InvalidFile)
  end

  it 'rechecks permissions on every planning call and binds them to the parsed file type' do
    role = create(:custom_role, account: account, permissions: ['contact_manage'])
    AccountUser.find_by!(account: account, user: actor).update!(role: :agent, custom_role: role)
    service = described_class.new(account: account, actor: actor, file: file, mapping: mapping, options: options)
    expect(service.call.errors).to be_empty
    role.update!(permissions: ['conversation_manage'])
    expect { service.call }.to raise_error(Pundit::NotAuthorizedError)
    role.update!(permissions: ['contact_manage'])
    combined = JrcCustomers::ImportFile.new(content: "company.name,contact.name\nCompany,Person\n", kind: 'both')
    forged = options.merge(kind: 'contacts')
    expect do
      described_class.new(account: account, actor: actor, file: combined, mapping: combined.metadata[:suggested_mapping], options: forged).call
    end.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'validates configured native labels without creating tags during preview' do
    account.labels.create!(title: 'known', color: '#22aa99')
    csv.replace("name,email,labels\nPerson,person@example.test,known\n")
    before = ActsAsTaggableOn::Tag.count
    expect(plan.errors).to be_empty
    expect(plan.rows.first[:labels]).to eq(['known'])
    expect(ActsAsTaggableOn::Tag.count).to eq(before)
  end

  it 'rejects unconfigured labels with the exact line and field' do
    csv.replace("name,labels\nPerson,unconfigured\n")
    expect(plan.errors).to include(hash_including(line: 2, field: 'labels', code: 'UNKNOWN_LABEL'))
    expect(account.contacts.count).to eq(0)
  end

  it 'can bind a valid batch larger than the shared ledger JSON limit without lowering the CSV limits' do
    csv.replace(CSV.generate do |table|
      table << %w[name email job_title department]
      250.times { |index| table << ['P' * 220, "wide#{index}@example.test", 'T' * 220, 'D' * 220] }
    end)
    expect(csv.bytesize).to be > JrcServiceDesk::CanonicalJson::MAX_BYTES
    expect(plan.errors).to be_empty
    expect(plan.rows.size).to eq(250)
    expect(plan.digest).to match(/\A[0-9a-f]{64}\z/)
    expect(account.contacts.count).to eq(0)
  end

  context 'with both company and contact columns' do
    let(:kind) { 'both' }
    let(:csv) do
      "company.name,company.tax_id,contact.name,contact.email,contact.company_role,contact.company_primary\n" \
        "Future company,11222333000181,First,first@example.test,finance,true\n" \
        "Future company,11222333000181,Second,second@example.test,technical,false\n"
    end

    it 'validates an unsaved company graph without fake IDs or preview writes and reuses only an explicit fiscal identity' do
      expect(plan.errors).to be_empty
      expect(plan.rows.select { |row| row[:entity] == 'company' }.pluck(:action)).to eq(%w[create reference])
      expect(plan.rows.select { |row| row[:entity] == 'contact' }.pluck(:action)).to eq(%w[create create])
      expect(plan.rows.pluck(:record_id)).to all(be_nil)
      expect(account.contacts.count).to eq(0)
      expect(account.master_companies.count).to eq(0)
    end

    it 'does not merge company rows solely because their names match' do
      csv.gsub!('11222333000181', '')
      expect(plan.errors).to include(hash_including(line: 3, entity: 'company', code: 'INVALID_COMPANY'))
    end

    it 'rejects conflicting values for the same explicitly identified company' do
      csv.sub!('Future company,11222333000181,Second', 'Different company,11222333000181,Second')
      expect(plan.errors).to include(hash_including(line: 3, entity: 'company', code: 'INVALID_COMPANY'))
    end

    it 'rejects multiple primary contacts for the same pending company' do
      csv.sub!('technical,false', 'technical,true')
      expect(plan.errors).to include(hash_including(line: 3, field: 'company_primary'))
    end
  end

  context 'with mapped company updates' do
    let(:kind) { 'companies' }
    let(:csv) { "id,name\n" }

    it 'retains existing values when skip is explicitly selected and never plans deletion by omission' do
      company = account.master_companies.create!(name: 'Original')
      csv << "#{company.id},Changed\n"
      options[:existing] = 'skip'
      expect(plan.errors).to be_empty
      expect(plan.rows.first).to include(action: 'skip', record_id: company.id, attributes: {})
      expect(company.reload.name).to eq('Original')
    end

    it 'does not bypass organizational coverage for an internal operating company' do
      hidden = account.master_companies.create!(name: 'Hidden operator', relationship_type: 'internal')
      account.jrc_crm_business_units.create!(operating_company: hidden, name: 'Hidden unit', code: 'HIDDEN')
      csv << "#{hidden.id},Changed\n"
      expect(plan.errors).to include(hash_including(line: 2, entity: 'company'))
      expect(hidden.reload.name).to eq('Hidden operator')
    end

    it 'masks a fiscal identifier even when the update file omits the existing person_kind' do
      company = account.master_companies.create!(name: 'Individual', person_kind: 'individual', tax_id: '11144477735')
      csv.replace("id,tax_id\n#{company.id},11144477735\n")
      expect(plan.errors).to be_empty
      expect(plan.rows.first[:attributes]).not_to have_key('person_kind')
      expect(plan.public_rows.first[:attributes]['tax_id']).to eq('***.***.***-35')
      expect(plan.public_rows.to_json).not_to include('11144477735')
    end
  end

  it 'keeps an unsaved company association in the same tenant during native model validation' do
    other = create(:account)
    contact = account.contacts.new(name: 'Draft', master_company: other.master_companies.new(name: 'Foreign'), company_role: 'finance')
    expect(contact).not_to be_valid
    expect(contact.errors[:company_id]).to include('must belong to this account')
    expect(other.master_companies.count).to eq(0)
  end
end

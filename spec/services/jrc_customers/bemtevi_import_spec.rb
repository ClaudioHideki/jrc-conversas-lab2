require 'rails_helper'

RSpec.describe JrcCustomers::BemteviImport do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:row) do
    {
      source_system: 'bemtevi', source_id: '17', source_status: 0, source_status_label: 'active', observed_at: Time.current.iso8601,
      eligible_for_import: true, review_reasons: [], snapshot_sha256: 'a' * 64, contact_data_source: 'snapshot',
      company: { name: 'Empresa Exemplo LTDA', trade_name: 'Exemplo', tax_id: '11222333000181', person_kind: 'organization',
                 relationship_type: 'customer', active: true, source: 'import', state_registration: 'IE-17', municipal_registration: nil },
      contact_points: [{ kind: 'mobile', value: '+5511999998888' }, { kind: 'email', value: 'contato@example.test' }],
      addresses: [{ source_id: '9', address_type: 'other', street: 'Rua Exemplo', district: 'Centro', postal_code: '01001000',
                    complement: nil, city: 'Sao Paulo', state: 'SP', country: 'BR' }]
    }
  end
  let(:content) { [row].to_json }
  let(:service) { described_class.new(account: account, actor: actor, content: content) }

  before { account.enable_features!('jrc_customer_master', 'jrc_crm') }

  it 'previews counts without creating companies, contacts, addresses or audits' do
    company_count = JrcCustomers::Company.count
    contact_count = Contact.count
    address_count = JrcCustomers::Address.count
    audit_count = JrcCrm::AuditEvent.count
    preview = service.preview
    expect(preview[:token]).to be_present
    expect(preview[:counts]).to include(companies_create: 1, quarantined: 0)
    expect([JrcCustomers::Company.count, Contact.count, JrcCustomers::Address.count, JrcCrm::AuditEvent.count])
      .to eq([company_count, contact_count, address_count, audit_count])
    expect(preview.except(:token).to_json).not_to include('Empresa Exemplo', 'contato@example.test', '+5511999998888')
  end

  it 'creates the canonical customer and an explicitly organizational contact with exact source provenance' do
    result = service.apply!(token: service.preview.fetch(:token))
    company = account.master_companies.find_by!(tax_id: '11222333000181')
    contact = account.contacts.find_by!(identifier: 'bemtevi:customer:17')
    expect(company).to have_attributes(relationship_type: 'customer', person_kind: 'organization', active: true,
                                       customer_code: format('EMP-%06d', company.id))
    expect(company.custom_attributes.dig('bemtevi', 'source_id')).to eq('17')
    expect(contact).to have_attributes(name: company.name, company_id: company.id, contact_type: 'customer', registration_status: 'registered')
    expect(contact.additional_attributes).to include('entity_type' => 'company', 'source_system' => 'bemtevi', 'source_id' => '17')
    expect(contact.contact_points.pluck(:normalized_value)).to contain_exactly('+5511999998888', 'contato@example.test')
    expect(company.addresses.first).to have_attributes(street: 'Rua Exemplo', city: 'Sao Paulo', country: 'BR')
    expect(result).to include(applied: 1, already_applied: 0)
  end

  it 'records the native import audit under the importing account and actor' do
    service.apply!(token: service.preview.fetch(:token))
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'customer_import_applied')).to exist
  end

  it 'replays the exact approved request without duplicate companies, contacts, addresses, points or audits' do
    token = service.preview.fetch(:token)
    service.apply!(token: token)
    counts = [JrcCustomers::Company.count, Contact.count, JrcCustomers::Address.count, JrcCustomers::ContactPoint.count, JrcCrm::AuditEvent.count]
    expect(service.apply!(token: token)).to include(applied: 0, already_applied: 1)
    expect([JrcCustomers::Company.count, Contact.count, JrcCustomers::Address.count, JrcCustomers::ContactPoint.count, JrcCrm::AuditEvent.count])
      .to eq(counts)
  end

  it 'rejects a modified dataset, another actor and another account before writing' do
    token = service.preview.fetch(:token)
    changed = described_class.new(account: account, actor: actor, content: content.sub('Empresa Exemplo', 'Outra Empresa'))
    expect { changed.apply!(token: token) }.to raise_error(described_class::InvalidImport)
    other_actor = create(:user, account: account, role: :administrator)
    expect { described_class.new(account: account, actor: other_actor, content: content).apply!(token: token) }
      .to raise_error(described_class::InvalidImport)
    other = create(:account)
    other.enable_features!('jrc_customer_master')
    create(:account_user, account: other, user: actor, role: :administrator)
    expect { described_class.new(account: other, actor: actor, content: content).apply!(token: token) }
      .to raise_error(described_class::InvalidImport)
    expect(account.master_companies).to be_empty
  end

  it 'rechecks current administrative membership and the enabled module' do
    token = service.preview.fetch(:token)
    account.account_users.find_by!(user: actor).update!(role: :agent)
    expect { service.apply!(token: token) }.to raise_error(Pundit::NotAuthorizedError)
    account.account_users.find_by!(user: actor).update!(role: :administrator)
    account.disable_features!('jrc_customer_master')
    expect { service.preview }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'quarantines observations older than 24 hours or from the future' do
    [25.hours.ago, 10.minutes.from_now].each do |observed|
      old = described_class.new(account: account, actor: actor, content: [row.merge(observed_at: observed.iso8601)].to_json)
      preview = old.preview
      expect(preview[:counts]).to include(quarantined: 1, companies_create: 0)
      expect(preview[:quarantine_reasons]).to include('stale_or_future_observation' => 1)
      expect(preview[:token]).to be_nil
    end
  end

  it 'does not trust the eligibility boolean to import inactive or invalid fiscal identities' do
    [[row.merge(source_status: 1)], [row.deep_merge(company: { tax_id: '00000000000000' })], [row.merge(eligible_for_import: false)]].each do |rows|
      preview = described_class.new(account: account, actor: actor, content: rows.to_json).preview
      expect(preview[:counts]).to include(quarantined: 1, companies_create: 0)
      expect(preview[:token]).to be_nil
    end
  end

  it 'quarantines duplicate source IDs and repeated fiscal identities instead of arbitrarily merging them' do
    [row.merge(source_id: '18'), row.deep_merge(company: { name: 'Same source ID' })].each do |other|
      preview = described_class.new(account: account, actor: actor, content: [row, other].to_json).preview
      expect(preview[:counts]).to include(quarantined: 2, companies_create: 0)
    end
  end

  it 'links a unique fiscal identity while preserving curated fields and unrelated custom attributes' do
    company = account.master_companies.create!(name: 'Nome revisado', trade_name: 'Fantasia revisada', tax_id: '11222333000181',
                                               relationship_type: 'customer', active: false, custom_attributes: { 'curated' => 'keep' })
    service.apply!(token: service.preview.fetch(:token))
    expect(company.reload).to have_attributes(name: 'Nome revisado', trade_name: 'Fantasia revisada', active: false, state_registration: 'IE-17')
    expect(company.custom_attributes).to include('curated' => 'keep')
    expect(company.custom_attributes.dig('bemtevi', 'source_id')).to eq('17')
    expect(account.master_companies.count).to eq(1)
  end

  it 'refuses conflicts between a prior source binding and a different fiscal company' do
    account.master_companies.create!(name: 'Binding', tax_id: '19131243000197', custom_attributes: { 'bemtevi' => { 'source_id' => '17' } })
    account.master_companies.create!(name: 'Fiscal match', tax_id: '11222333000181')
    preview = service.preview
    expect(preview[:quarantine_reasons]).to include('company_identity_conflict' => 1)
    expect(preview[:token]).to be_nil
  end

  it 'never converts an internal issuer to a commercial customer or overwrites another source binding' do
    company = account.master_companies.create!(name: 'Internal', tax_id: '11222333000181', relationship_type: 'internal')
    expect(service.preview[:quarantine_reasons]).to include('internal_company_conflict' => 1)
    company.update!(relationship_type: 'customer', custom_attributes: { 'bemtevi' => { 'source_id' => '88' } })
    expect(service.preview[:quarantine_reasons]).to include('source_binding_conflict' => 1)
  end

  it 'does not match an existing company only by name or cross another account boundary' do
    duplicate_name = account.master_companies.create!(name: 'Empresa Exemplo LTDA')
    expect(service.preview[:quarantine_reasons]).to include('unreviewed_name_match' => 1)
    duplicate_name.destroy!
    foreign = create(:account)
    foreign_company = foreign.master_companies.create!(name: 'Foreign', tax_id: '11222333000181')
    service.apply!(token: service.preview.fetch(:token))
    expect(account.master_companies.count).to eq(1)
    expect(foreign_company.reload.custom_attributes).to eq({})
  end

  it 'invalidates an approval if the matched company changes after preview' do
    company = account.master_companies.create!(name: 'Original', tax_id: '11222333000181')
    token = service.preview.fetch(:token)
    company.update!(name: 'Updated while preview open')
    expect { service.apply!(token: token) }.to raise_error(described_class::InvalidImport)
    expect(company.reload.custom_attributes['bemtevi']).to be_nil
  end

  it 'preserves blocked contacts and never links an existing person with an unconfirmed company' do
    person = create(:contact, account: account, phone_number: '+5511999998888', blocked: true)
    preview = service.preview
    expect(preview[:point_quarantine_reasons]).to include('contact_company_unconfirmed' => 1)
    service.apply!(token: preview.fetch(:token))
    expect(person.reload).to have_attributes(blocked: true, company_id: nil)
    company = account.master_companies.first
    expect(company.custom_attributes.dig('bemtevi', 'pending_contact_points').first)
      .to include('kind' => 'mobile', 'value' => '+5511999998888', 'reason' => 'contact_company_unconfirmed')
    expect(account.contacts.find_by(identifier: 'bemtevi:customer:17').phone_number).to be_nil
  end

  it 'quarantines shared points without preventing the canonical company import' do
    contacts = Array.new(2) { create(:contact, account: account) }
    contacts.each { |contact| contact.contact_points.create!(account: account, kind: 'mobile', value: '+5511999998888') }
    preview = service.preview
    expect(preview[:point_quarantine_reasons]).to include('ambiguous_contact_point' => 1)
    result = service.apply!(token: preview.fetch(:token))
    expect(result[:applied]).to eq(1)
    expect(contacts.map { |contact| contact.reload.company_id }).to eq([nil, nil])
  end

  it 'does not reassign a point owned by another company and reuses an exact same-company contact' do
    company = account.master_companies.create!(name: 'Existing', tax_id: '11222333000181')
    same = create(:contact, account: account, company_id: company.id, email: 'contato@example.test', blocked: true)
    other_company = account.master_companies.create!(name: 'Another')
    other = create(:contact, account: account, company_id: other_company.id, phone_number: '+5511999998888')
    preview = service.preview
    expect(preview[:point_quarantine_reasons]).to include('contact_company_conflict' => 1)
    service.apply!(token: preview.fetch(:token))
    expect(same.reload).to have_attributes(blocked: true, company_id: company.id)
    expect(same.contact_points.pluck(:normalized_value)).to include('contato@example.test')
    expect(other.reload.company_id).to eq(other_company.id)
  end

  it 'does not guess that the same phone in two source customers belongs to one organizational contact' do
    other = row.deep_merge(source_id: '18', company: { name: 'Another', tax_id: '19131243000197' })
    preview = described_class.new(account: account, actor: actor, content: [row, other].to_json).preview
    expect(preview[:point_quarantine_reasons]).to include('shared_point_across_source_customers' => 4)
    result = described_class.new(account: account, actor: actor, content: [row, other].to_json).apply!(token: preview.fetch(:token))
    expect(result[:applied]).to eq(2)
    expect(account.contacts).to be_empty
  end

  it 'does not create contacts when no usable communication point was supplied' do
    empty = described_class.new(account: account, actor: actor, content: [row.merge(contact_points: [])].to_json)
    expect { empty.apply!(token: empty.preview.fetch(:token)) }.not_to change(Contact, :count)
    expect(account.master_companies.count).to eq(1)
  end

  it 'deduplicates existing addresses while retaining ERP address provenance' do
    company = account.master_companies.create!(name: 'Existing', tax_id: '11222333000181')
    company.addresses.create!(account: account, **row[:addresses].first.except(:source_id))
    service.apply!(token: service.preview.fetch(:token))
    expect(company.addresses.count).to eq(1)
    expect(company.reload.custom_attributes.dig('bemtevi', 'address_links').first).to include('source_id' => '9')
  end

  it 'rolls the whole import back if a required audit fails' do
    allow(JrcCustomers::Audit).to receive(:record!).and_call_original
    allow(JrcCustomers::Audit).to receive(:record!).with(hash_including(event_type: 'customer_import_applied'))
                                                   .and_raise(ActiveRecord::RecordInvalid.new(JrcCrm::AuditEvent.new))
    token = service.preview.fetch(:token)
    expect { service.apply!(token: token) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(account.master_companies).to be_empty
    expect(account.contacts).to be_empty
    expect(JrcCustomers::Address.where(account: account)).to be_empty
  end

  it 'does not create messages or campaign authorizations during import' do
    before_messages = Message.count
    service.apply!(token: service.preview.fetch(:token))
    expect(Message.count).to eq(before_messages)
    account.contacts.pluck(:custom_attributes).each do |attributes|
      expect(attributes.keys & %w[whatsapp_consent campaign_consent consent]).to be_empty
    end
  end

  it 'rejects credentials and unsupported company fields rather than persisting them as customer metadata' do
    invalid = described_class.new(account: account, actor: actor, content: [row.deep_merge(company: { password: 'NEVER_STORE' })].to_json)
    expect { invalid.preview }.to raise_error(described_class::InvalidImport)
  end

  it 'rejects structured values inside company scalar fields' do
    invalid = described_class.new(account: account, actor: actor,
                                  content: [row.deep_merge(company: { name: { nested: 'NEVER_STORE' } })].to_json)
    expect { invalid.preview }.to raise_error(described_class::InvalidImport)
  end

  it 'matches a normalized fiscal identity when legacy data retains document punctuation' do
    company = account.master_companies.create!(name: 'Curated legacy customer', tax_id: '11222333000181')
    # Reproduce pre-normalization legacy storage; a model save normalizes it.
    # rubocop:disable Rails/SkipsModelValidations
    company.update_column(:tax_id, '11.222.333/0001-81')
    # rubocop:enable Rails/SkipsModelValidations
    preview = service.preview
    expect(preview[:counts]).to include(companies_create: 0, companies_update: 1, quarantined: 0)
    service.apply!(token: preview.fetch(:token))
    expect(company.reload.custom_attributes.dig('bemtevi', 'source_id')).to eq('17')
    expect(account.master_companies.count).to eq(1)
  end

  it 'quarantines an orphan organization identifier while importing its canonical company' do
    contact = create(:contact, account: account, identifier: 'bemtevi:customer:17',
                               additional_attributes: { entity_type: 'company', source_system: 'bemtevi', source_id: '17' })
    preview = service.preview
    expect(preview[:point_quarantine_reasons]).to include('organizational_contact_conflict' => 2)
    expect(service.apply!(token: preview.fetch(:token))).to include(applied: 1)
    expect(contact.reload.company_id).to be_nil
    expect(contact.contact_points).to be_empty
  end

  it 'expires an unused approval instead of importing with an old preview' do
    token = service.preview.fetch(:token)
    travel 16.minutes do
      expect { service.apply!(token: token) }.to raise_error(described_class::InvalidImport)
    end
    expect(account.master_companies).to be_empty
  end
end

require 'rails_helper'

RSpec.describe JrcCustomers::ImportContactFields do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:runs) { JrcCustomers::ImportRuns.new(account: account, actor: actor) }
  let(:service) { described_class.new(account: account) }

  before { account.enable_features!('jrc_customer_master', 'companies') }

  it 'offers only configured contact fields in the current account, including keys containing dots' do
    create(:custom_attribute_definition, account: account, attribute_model: :contact_attribute, attribute_key: 'customer.tier')
    create(:custom_attribute_definition, account: account, attribute_model: :conversation_attribute, attribute_key: 'case_only')
    create(:custom_attribute_definition, attribute_model: :contact_attribute, attribute_key: 'foreign_only')
    fields = runs.fields_for('contacts')
    expect(fields).to include('contact.custom_attributes.customer.tier', 'contact.city', 'contact.company_name')
    expect(fields).not_to include('contact.custom_attributes.foreign_only', 'contact.custom_attributes.case_only', 'contact.account_id')
  end

  it 'converts configured values using the existing typed resource validation and retains native informational fields' do
    create(:custom_attribute_definition, account: account, attribute_model: :contact_attribute, attribute_key: 'enabled',
                                         attribute_display_type: :checkbox)
    create(:custom_attribute_definition, account: account, attribute_model: :contact_attribute, attribute_key: 'amount',
                                         attribute_display_type: :currency)
    values = { 'custom_attributes.enabled' => 'false', 'custom_attributes.amount' => '12.50', 'city' => 'São Paulo' }
    service.apply!(values)
    expect(values).to eq('custom_attributes' => { 'enabled' => false, 'amount' => 12.5 }, 'additional_attributes' => { 'city' => 'São Paulo' })
  end

  it 'reports invalid configured lists, booleans, dates and formats without echoing private values' do
    definitions = [[:list, 'list', { attribute_values: %w[gold silver] }, 'private-value'],
                   [:checkbox, 'bool', {}, 'yes'], [:date, 'date', {}, '2026-02-30'],
                   [:text, 'format', { regex_pattern: '\\A[A-Z]{3}\\z' }, 'private-value']]
    definitions.each do |type, key, attributes, value|
      create(:custom_attribute_definition, account: account, attribute_model: :contact_attribute, attribute_key: key,
                                           attribute_display_type: type, **attributes)
      expect do
        service.apply!({ "custom_attributes.#{key}" => value })
      end.to raise_error(JrcCustomers::ImportIssue) { |error| expect(error.message).not_to include(value) }
    end
  end

  it 'preserves existing JSON keys and the real linked company name instead of resolving a company by its CSV name' do
    company = create(:company, account: account, name: 'Canonical')
    contact = create(:contact, account: account, company_id: company.id, custom_attributes: { keep: 'before' },
                               additional_attributes: { city: 'Before', country: 'BR' })
    values = { 'custom_attributes' => { 'new' => 'after' }, 'additional_attributes' => { 'city' => 'After', 'company_name' => 'Unlinked name' } }
    service.merge!(contact, values)
    expect(values.fetch('custom_attributes')).to include('keep' => 'before', 'new' => 'after')
    expect(values.fetch('additional_attributes')).to include('city' => 'After', 'country' => 'BR', 'company_name' => 'Canonical')
  end

  it 'keeps the complete configured fields through private upload, read-only preview and actual native execution' do
    create(:custom_attribute_definition, account: account, attribute_model: :contact_attribute, attribute_key: 'tier',
                                         attribute_display_type: :list, attribute_values: %w[gold silver])
    content = "name,email,city,company_name,custom_attributes.tier\nImported,imported@example.test,City,Informational company,gold\n"
    run = runs.create!(kind: 'contacts', content: content, filename: 'configured.csv')
    file = runs.file(run)
    review = JrcCustomers::ImportReview.new(account: account, actor: actor)
    preview = review.preview!(id: run.id, mapping: file.metadata.fetch(:suggested_mapping), options: { existing: 'update' })
    expect(preview.fetch(:plan).errors).to be_empty
    expect(account.contacts.count).to eq(0)
    JrcCustomers::ImportExecution.new(account: account, actor: actor).apply!(id: run.id, token: preview.fetch(:token), confirmed: true)
    contact = account.contacts.find_by!(email: 'imported@example.test')
    expect(contact.custom_attributes).to include('tier' => 'gold')
    expect(contact.additional_attributes).to include('city' => 'City', 'company_name' => 'Informational company')
    expect(contact.company_id).to be_nil
    expect(account.companies.count).to eq(0)
  end

  it 'does not apply a previously offered field after its configuration is removed or moved to another model' do
    definition = create(:custom_attribute_definition, account: account, attribute_model: :contact_attribute, attribute_key: 'tier')
    run = runs.create!(kind: 'contacts', content: "name,custom_attributes.tier\nName,1\n", filename: 'configured.csv')
    file = runs.file(run)
    mapping = file.metadata.fetch(:suggested_mapping)
    definition.update!(attribute_model: :conversation_attribute)
    expect do
      JrcCustomers::ImportReview.new(account: account, actor: actor).preview!(id: run.id, mapping: mapping, options: { existing: 'update' })
    end.to raise_error(JrcCustomers::ImportFile::InvalidFile)
    expect(account.contacts.count).to eq(0)
  end
end

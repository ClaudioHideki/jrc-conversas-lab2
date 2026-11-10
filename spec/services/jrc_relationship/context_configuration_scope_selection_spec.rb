require 'rails_helper'

RSpec.describe JrcRelationship::Context do
  let(:account) { create(:account) }
  let(:manager) { create(:user, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: manager) }
  let(:context) { described_class.new(member) }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC configuration customer') }
  let(:unit) { JrcCrm::BusinessUnit.create!(account: account, name: 'SYNTHETIC native unit', code: 'CONFIG') }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, company: company, business_unit: unit, owner: manager) }
  let!(:general) { JrcRelationship::Configuration.create!(account: account, rules: { no_contact_days: 30 }) }
  let(:company_config) { JrcRelationship::Configuration.create!(account: account, scope_key: "company:#{company.id}", rules: { no_contact_days: 7 }) }
  let(:unit_config) { JrcRelationship::Configuration.create!(account: account, scope_key: "unit:#{unit.id}", rules: { no_contact_days: 14 }) }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'preserves the account configuration for global operations and assignments with no specific configuration' do
    expect(context.configuration).to eq(general)
    expect(context.configuration(assignment)).to eq(general)
  end

  it 'uses an existing company configuration before the general fallback' do
    company_config
    expect(context.configuration(assignment)).to eq(company_config)
    expect(context.configuration(assignment).effective_rules['no_contact_days']).to eq(7)
  end

  it 'uses an existing native unit configuration when there is no company configuration' do
    unit_config
    expect(context.configuration(assignment)).to eq(unit_config)
    expect(context.configuration(assignment).effective_rules['no_contact_days']).to eq(14)
  end

  it 'preserves company precedence over unit' do
    unit_config
    company_config
    expect(context.configuration(assignment)).to eq(company_config)
  end

  it 'preserves segment precedence over company and unit' do
    company_config
    unit_config
    segment = JrcCustomers::Taxonomy.create!(account: account, kind: 'segment', name: 'SYNTHETIC configuration segment')
    assignment.update!(settings: { segment_id: segment.id })
    selected = JrcRelationship::Configuration.create!(account: account, scope_key: "segment:#{segment.id}")
    expect(context.configuration(assignment)).to eq(selected)
  end

  it 'preserves product precedence over segment, company and unit' do
    company_config
    unit_config
    segment = JrcCustomers::Taxonomy.create!(account: account, kind: 'segment', name: 'SYNTHETIC product segment')
    product = create(:jrc_crm_product, account: account)
    assignment.update!(settings: { segment_id: segment.id, product_id: product.id })
    JrcRelationship::Configuration.create!(account: account, scope_key: "segment:#{segment.id}")
    selected = JrcRelationship::Configuration.create!(account: account, scope_key: "product:#{product.id}")
    expect(context.configuration(assignment)).to eq(selected)
  end
end

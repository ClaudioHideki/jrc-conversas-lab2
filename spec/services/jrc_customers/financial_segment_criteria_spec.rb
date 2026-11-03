require 'rails_helper'

RSpec.describe JrcCustomers::FinancialSegmentCriteria do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:company) { account.master_companies.create!(name: 'Financial customer') }
  let(:empty) { account.master_companies.create!(name: 'Without authorized billing') }
  let(:person) { create(:contact, account: account, company_id: company.id) }
  let(:rule) do
    { 'field' => 'invoiced_revenue', 'operator' => 'at_least', 'value' => '123.45',
      'period_start' => '2026-10-01', 'period_end' => '2026-10-31' }
  end
  let(:query) { described_class.new(account: account, actor: actor, scope: account.master_companies) }
  let!(:order) do
    account.jrc_crm_sales_orders.create!(owner: actor, contact: person, source_type: 'manual', order_origin: 'direct_sale',
                                         status: 'invoiced', total_cents: 12_345, sold_at: '2026-10-15T12:00:00Z')
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_crm') }

  it 'sums invoiced order totals in the chosen period, excludes pending and canceled orders, and never counts receipts' do
    %w[pending canceled].each do |status|
      account.jrc_crm_sales_orders.create!(owner: actor, contact: person, source_type: 'manual', order_origin: 'direct_sale',
                                           status: status, total_cents: 99_999, sold_at: order.sold_at)
    end
    expect(query.call(rule).pluck(:id)).to eq([company.id])
    expect(query.call(rule.merge('value' => '123.46')).pluck(:id)).to eq([])
    expect(query.call(rule.merge('period_start' => '2026-11-01', 'period_end' => '2026-11-30')).pluck(:id)).to eq([])
  end

  it 'uses inclusive dates in the account timezone and the native sold/closed/created precedence' do
    account.update!(reporting_timezone: 'America/Sao_Paulo')
    order.update!(sold_at: Time.iso8601('2026-11-01T02:59:59Z'))
    expect(query.call(rule).pluck(:id)).to eq([company.id])
    order.update!(sold_at: Time.iso8601('2026-11-01T03:00:00Z'))
    expect(query.call(rule).pluck(:id)).to eq([])
    order.update!(sold_at: nil, closed_at: Time.iso8601('2026-10-15T12:00:00Z'))
    expect(query.call(rule).pluck(:id)).to eq([company.id])
  end

  it 'aggregates shipped/completed orders once across canonical contacts and reevaluates source changes' do
    second = create(:contact, account: account, company_id: company.id)
    %w[shipped completed].each do |status|
      account.jrc_crm_sales_orders.create!(owner: actor, contact: second, source_type: 'manual', order_origin: 'direct_sale',
                                           status: status, total_cents: 100, sold_at: order.sold_at)
    end
    expect(query.call(rule.merge('operator' => 'equal_to', 'value' => '125.45')).pluck(:id)).to eq([company.id])
    second.update!(company_id: nil)
    expect(query.call(rule.merge('operator' => 'equal_to', 'value' => '123.45')).pluck(:id)).to eq([company.id])
  end

  it 'keeps ownership, organizational and account restrictions before calculating even with manual inclusions' do
    company
    empty
    hidden_owner = create(:user, account: account, role: :agent)
    order.update!(owner: hidden_owner)
    account.account_users.find_by!(user: actor).update!(role: :agent)
    expect(query.call(rule).pluck(:id)).to eq([])
    expect(query.call(rule.merge('operator' => 'equal_to', 'value' => '0')).pluck(:id)).to contain_exactly(company.id, empty.id)
    account.account_users.find_by!(user: actor).destroy!
    expect { query.call(rule) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'denies unavailable CRM permissions rather than treating inaccessible financial data as zero in negated rules' do
    account.disable_features!('jrc_crm')
    expect { query.call(rule.merge('operator' => 'not_equal_to', 'value' => '0')) }.to raise_error(Pundit::NotAuthorizedError)
    account.enable_features!('jrc_crm')
    role = create(:custom_role, account: account, permissions: ['contact_manage'])
    account.account_users.find_by!(user: actor).update!(role: :agent, custom_role: role)
    expect { query.call(rule.merge('operator' => 'at_most', 'value' => '0')) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'counts only native active and expiring contracts without replacing undefined TRR with recurring revenue' do
    contract = account.jrc_crm_contracts.create!(sales_order: order, contact: person, owner: actor)
    File.open(Rails.root.join('spec/assets/sample.pdf')) do |file|
      contract.signed_document.attach(io: file, filename: 'synthetic-signed.pdf', content_type: 'application/pdf')
    end
    contract.update!(status: 'active', signature_status: 'signed', signature_mode: 'manual',
                     signed_by_name: 'Synthetic customer', signed_at: Time.current)
    count_rule = { 'field' => 'active_contract_count', 'operator' => 'at_least', 'value' => '1' }
    expect(query.call(count_rule).pluck(:id)).to eq([company.id])
    contract.update!(status: 'ended')
    expect(query.call(count_rule).pluck(:id)).to eq([])
    expect(JrcCustomers::SegmentCriteria::FIELDS).not_to include('trr')
  end

  it 'combines financial and directory rules and preserves explicit inclusions and exclusions' do
    taxonomy = JrcCustomers::Taxonomy.create!(account: account, name: 'Invoiced', kind: 'segment', selection_mode: 'dynamic',
                                              criteria: { match: 'all', rules: [rule] })
    members = JrcCustomers::SegmentMembers.new(account: account, actor: actor, taxonomy: taxonomy)
    expect(members.companies.pluck(:id)).to eq([company.id])
    JrcCustomers::SegmentOverride.create!(account: account, taxonomy: taxonomy, company: company, mode: 'exclude')
    JrcCustomers::SegmentOverride.create!(account: account, taxonomy: taxonomy, company: empty, mode: 'include')
    expect(members.companies.pluck(:id)).to eq([empty.id])
  end

  it 'rejects ambiguous dates, reversed ranges, floats, negative or unbounded amounts and unauthorized DSL fields' do
    [nil, '2026-02-30', '01/10/2026', '2026-11-01'].each do |date|
      expect(described_class.error(rule.merge('period_start' => date))).to be_present
    end
    ['-1', '1,00', '1.001', '1e6', '1000000000000', 1.0].each do |value|
      expect(described_class.error(rule.merge('value' => value))).to be_present
    end
    expect(described_class.error(rule)).to be_nil
    expect(JrcCustomers::SegmentCriteria.rule_error(rule.merge('account_id' => account.id))).to be_present
    expect(JrcCustomers::SegmentCriteria.rule_error(rule.merge('field' => 'trr'))).to be_present
  end
end

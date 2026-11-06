require 'rails_helper'

RSpec.describe JrcCustomers::ModuleSegmentFilter do
  it 'evaluates one thousand persisted customers and invoice sources with native CRM scope and real pagination' do
    expect(ActiveRecord::Base.connection.select_value('SELECT current_database()')).to eq('jrc_rel_v2_candidate_test')
    account = create(:account)
    account.enable_features!('jrc_customer_master', 'jrc_crm')
    actor = create(:user, account: account, role: :administrator)
    setup_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    matching = []
    companies = []
    leads = []
    orders = []
    1_000.times do |index|
      company = account.master_companies.create!(name: "Synthetic financial scale #{index}")
      contact = create(:contact, account: account, company_id: company.id)
      order = account.jrc_crm_sales_orders.create!(
        owner: actor, contact: contact, source_type: 'manual', order_origin: 'direct_sale',
        status: index % 4 == 1 ? 'pending' : 'invoiced', total_cents: index % 4 == 3 ? 5_000 : 10_000,
        sold_at: index % 4 == 2 ? '2026-09-15T12:00:00Z' : '2026-10-15T12:00:00Z'
      )
      lead = account.jrc_crm_leads.create!(name: 'Synthetic scale lead', owner: actor, contact: contact)
      matching << lead.id if (index % 4).zero?
      companies << company
      leads << lead
      orders << order
    end
    rule = { 'field' => 'invoiced_revenue', 'operator' => 'at_least', 'value' => '100.00',
             'period_start' => '2026-10-01', 'period_end' => '2026-10-31' }
    taxonomy = JrcCustomers::Taxonomy.create!(account: account, name: 'Synthetic invoiced period', kind: 'segment', selection_mode: 'dynamic',
                                              modules: ['crm'], criteria: { match: 'all', rules: [rule] })
    native = JrcCustomers::Visibility.new(account: account, user: actor, account_user: account.account_users.find_by!(user: actor))
                                     .crm(account.jrc_crm_leads)
    filter = described_class.new(account: account, actor: actor, module_key: 'crm', segment_id: taxonomy.id)
    setup_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - setup_started
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    selected = filter.call(native, company_column: :company_id, contact_column: :contact_id).order(:id)
    expect(selected.count).to eq(250)
    pages = 9.times.flat_map { |page| selected.offset(page * 30).limit(30).pluck(:id) }
    expect(pages).to eq(matching)
    expect([selected.offset(270).limit(30).pluck(:id),
            filter.call(native.where.not(id: matching.first), contact_column: :contact_id).count]).to eq([[], 249])
    query_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    JrcCustomers::SegmentOverride.create!(account: account, taxonomy: taxonomy, company: companies.first, mode: 'exclude')
    JrcCustomers::SegmentOverride.create!(account: account, taxonomy: taxonomy, company: companies.second, mode: 'include')
    expect(filter.call(native, contact_column: :contact_id).pluck(:id)).to match_array(matching.drop(1) + [leads.second.id])
    orders[4].update!(status: 'canceled')
    expect([filter.call(native, contact_column: :contact_id).count, account.master_companies.count]).to eq([249, 1_000])
    expect(described_class.new(account: account, actor: actor, module_key: 'crm', segment_id: nil).call(native)).to equal(native)
    puts({ synthetic_customers: 1_000, synthetic_orders: 1_000, synthetic_leads: 1_000, matched: 250,
           setup_seconds: setup_seconds.round(3), paginated_query_seconds: query_seconds.round(3) }.to_json)
  end
end

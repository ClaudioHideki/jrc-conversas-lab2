require 'rails_helper'

RSpec.describe JrcCustomers::Timeline do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:company) { account.master_companies.create!(name: 'Timeline') }
  let(:context) do
    JrcCustomers::Customer360.new(account: account, user: user,
      account_user: account.account_users.find_by!(user_id: user.id), company: company)
  end
  let(:service) { described_class.new(context: context, account: account, user: user) }
  before do
    account.enable_features!('jrc_customer_master', 'jrc_crm')
    4.times do |i|
      JrcCustomers::Audit.record!(account: account, actor: user, resource: company, event_type: 'customer_company_updated', metadata: { private_snapshot: "hidden-#{i}" })
    end
  end

  it 'paginates existing audit events without duplicates' do
    first = service.call(limit: 2)
    second = service.call(cursor: first[:next_cursor], limit: 2)
    ids = first[:payload].map { |r| r[:id] } + second[:payload].map { |r| r[:id] }
    expect(ids.uniq.size).to eq(4)
    expect(second[:next_cursor]).to be_nil
  end
  it 'does not return private snapshot metadata' do
    expect(service.call.to_json).not_to include('hidden-')
    expect(service.call[:payload].first).not_to have_key(:metadata)
  end
  it 'binds pagination to the company and user' do
    cursor = service.call(limit: 1)[:next_cursor]
    other = account.master_companies.create!(name: 'Other company')
    other_context = JrcCustomers::Customer360.new(account: account, user: user,
      account_user: account.account_users.find_by!(user_id: user.id), company: other)
    other_service = described_class.new(context: other_context, account: account, user: user)
    expect { other_service.call(cursor: cursor) }.to raise_error(described_class::InvalidCursor)
  end
  it 'does not invent data for missing modules' do
    overview = context.overview
    expect(overview[:capabilities]).to include(service_desk: false, projects: false, contracts: false, central_sip_cdr: false)
    expect(overview).not_to have_key(:tickets_open)
    expect(overview).not_to have_key(:contracts_active)
  end
end

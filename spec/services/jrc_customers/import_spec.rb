require 'rails_helper'

RSpec.describe JrcCustomers::CompanyImport do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:csv) { "name,person_kind,tax_id,relationship_type\nImported,organization,11222333000181,prospect\n" }
  let(:service) { described_class.new(account: account, actor: actor, content: csv) }
  before { account.enable_features!('jrc_customer_master') }

  it 'previews without writing companies or audits' do
    expect { expect(service.preview[:token]).to be_present }.not_to change(JrcCustomers::Company, :count)
  end
  it 'applies exactly the reviewed content' do
    token = service.preview[:token]
    expect(service.apply!(token: token)[:applied]).to eq(1)
    expect(account.master_companies.first.tax_id).to eq('11222333000181')
  end
  it 'rejects a changed file' do
    token = service.preview[:token]
    other = described_class.new(account: account, actor: actor, content: csv.sub('Imported', 'Changed'))
    expect { other.apply!(token: token) }.to raise_error(described_class::InvalidImport)
  end
  it 'rejects a replayed token after the original create plan has been applied' do
    token = service.preview[:token]
    service.apply!(token: token)
    expect { service.apply!(token: token) }.to raise_error(described_class::InvalidImport)
  end
  it 'binds the preview to the user and account' do
    token = service.preview[:token]
    other = create(:account)
    service2 = described_class.new(account: other, actor: actor, content: csv)
    expect { service2.apply!(token: token) }.to raise_error(described_class::InvalidImport)
  end
  it 'returns row errors instead of silently merging matching names' do
    account.master_companies.create!(name: 'Imported')
    expect(service.preview[:errors]).not_to be_empty
    expect(service.preview[:token]).to be_nil
  end
  it 'rejects duplicate fiscal identifiers in one file' do
    repeated = described_class.new(account: account, actor: actor, content: csv + "Another,organization,11.222.333/0001-81,lead\n")
    expect(repeated.preview[:errors]).not_to be_empty
  end
  it 'blocks invalid CSV before any writes' do
    invalid = described_class.new(account: account, actor: actor, content: "name,unknown\nHello,world\n")
    expect { invalid.preview }.to raise_error(described_class::InvalidImport)
  end
end

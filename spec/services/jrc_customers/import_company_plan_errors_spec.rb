require 'rails_helper'

RSpec.describe JrcCustomers::ImportCompanyPlan do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }

  before { account.enable_features!('jrc_customer_master') }

  it 'retains the legacy error text and adds a real field/code for a malformed parent reference' do
    csv = "name,parent_company_id\nImported,private-source-value\n"
    legacy = JrcCustomers::CompanyImport.new(account: account, actor: actor, content: csv).preview
    expect(legacy[:errors].first).to include(line: 2, field: 'parent_company_id', code: 'INVALID_REFERENCE')
    expect(legacy[:errors].first[:error]).to include('invalid value for Integer')
    file = JrcCustomers::ImportFile.new(content: csv, kind: 'companies')
    plan = JrcCustomers::ImportPlan.new(account: account, actor: actor, file: file, mapping: file.metadata[:suggested_mapping],
                                        options: { existing: 'update' }).call
    expect(plan.errors.first).to include(line: 2, field: 'parent_company_id', code: 'INVALID_REFERENCE')
    expect(plan.errors.to_json).not_to include('private-source-value')
    expect(account.master_companies.count).to eq(0)
  end

  it 'does not echo a mis-mapped private value used as a company internal ID' do
    file = JrcCustomers::ImportFile.new(content: "name,id\nImported,private-source-value\n", kind: 'companies')
    plan = JrcCustomers::ImportPlan.new(account: account, actor: actor, file: file, mapping: file.metadata[:suggested_mapping],
                                        options: { existing: 'update' }).call
    expect(plan.errors.first).to include(line: 2, field: 'id', code: 'INVALID_REFERENCE')
    expect(plan.errors.to_json).not_to include('private-source-value')
    expect(account.master_companies.count).to eq(0)
  end

  it 'returns the validated boolean field without replacing the native validator or accepting an invalid company' do
    file = JrcCustomers::ImportFile.new(content: "name,active\nImported,invalid\n", kind: 'companies')
    plan = JrcCustomers::ImportPlan.new(account: account, actor: actor, file: file, mapping: file.metadata[:suggested_mapping],
                                        options: { existing: 'update' }).call
    expect(plan.errors.first).to include(line: 2, field: 'active', code: 'INVALID_COMPANY', message: 'active must be true or false')
    expect(account.master_companies.count).to eq(0)
  end
end

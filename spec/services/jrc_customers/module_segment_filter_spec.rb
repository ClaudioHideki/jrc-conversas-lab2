require 'rails_helper'

RSpec.describe JrcCustomers::ModuleSegmentFilter do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:taxonomy) { JrcCustomers::Taxonomy.create!(account: account, name: 'Published CRM segment', kind: 'segment', modules: ['crm']) }
  let(:company) { account.master_companies.create!(name: 'Selected company', segment: taxonomy.name) }
  let(:other) { account.master_companies.create!(name: 'Other company') }
  let(:person) { create(:contact, account: account, company_id: company.id) }
  let(:outsider) { create(:contact, account: account, company_id: other.id) }
  let!(:lead) { account.jrc_crm_leads.create!(name: 'Visible lead', owner: actor, contact: person) }
  let!(:unmatched) { account.jrc_crm_leads.create!(name: 'Unmatched lead', owner: actor, contact: outsider) }
  let(:relation) { account.jrc_crm_leads.where(owner_id: actor.id) }
  let(:filter) { described_class.new(account: account, actor: actor, module_key: 'crm', segment_id: taxonomy.id) }

  before { account.enable_features!('jrc_customer_master', 'jrc_crm') }

  it 'returns the exact native relation without additional authorization or queries when no filter is selected' do
    account.disable_features!('jrc_customer_master')
    query = described_class.new(account: account, actor: actor, module_key: 'crm', segment_id: nil)
    expect(query.call(relation)).to equal(relation)
  end

  it 'intersects native ownership and does not grant another owners record through company membership' do
    other_actor = create(:user, account: account, role: :agent)
    hidden = account.jrc_crm_leads.create!(name: 'Another owners lead', owner: other_actor, contact: person)
    result = filter.call(relation, company_column: :company_id, contact_column: :contact_id)
    expect(result.pluck(:id)).to eq([lead.id])
    expect(result.pluck(:id)).not_to include(unmatched.id, hidden.id)
  end

  it 'uses contact membership when present so a company match cannot undo an explicit contact exclusion' do
    JrcCustomers::SegmentOverride.create!(account: account, taxonomy: taxonomy, contact: person, mode: 'exclude')
    JrcCustomers::SegmentOverride.create!(account: account, taxonomy: taxonomy, contact: outsider, mode: 'include')
    result = filter.call(relation, company_column: :company_id, contact_column: :contact_id)
    expect(result.pluck(:id)).to eq([unmatched.id])
  end

  it 'supports canonical company-only records without inferring a person from names or other models' do
    lead.update!(contact_id: nil, company_id: company.id)
    expect(filter.call(relation, company_column: :company_id, contact_column: :contact_id).pluck(:id)).to eq([lead.id])
  end

  it 'recomputes dynamic membership and retains manual exclusions without persisting a parallel customer list' do
    taxonomy.update!(selection_mode: 'dynamic', criteria: { match: 'all', rules: [
                       { field: 'relationship_type', operator: 'equal_to', value: 'customer' }
                     ] })
    company.update!(relationship_type: 'customer')
    other.update!(relationship_type: 'prospect')
    expect(filter.call(relation, company_column: :company_id, contact_column: :contact_id).pluck(:id)).to eq([lead.id])
    other.update!(relationship_type: 'customer')
    expect(filter.call(relation, company_column: :company_id, contact_column: :contact_id).pluck(:id)).to contain_exactly(lead.id, unmatched.id)
    JrcCustomers::SegmentOverride.create!(account: account, taxonomy: taxonomy, contact: outsider, mode: 'exclude')
    expect(filter.call(relation, company_column: :company_id, contact_column: :contact_id).pluck(:id)).to eq([lead.id])
  end

  it 'rejects unpublished and inactive segments and rechecks publication on every call' do
    taxonomy.update!(modules: ['service_desk'])
    expect { filter.call(relation, contact_column: :contact_id) }.to raise_error(ActiveRecord::RecordNotFound)
    taxonomy.update!(modules: ['crm'], active: false)
    expect { filter.call(relation, contact_column: :contact_id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'rejects a foreign account segment even when the actor belongs to both accounts' do
    foreign = create(:account)
    foreign.enable_features!('jrc_customer_master')
    create(:account_user, account: foreign, user: actor, role: :administrator)
    foreign_segment = JrcCustomers::Taxonomy.create!(account: foreign, name: 'Foreign segment', kind: 'segment', modules: ['crm'])
    query = described_class.new(account: account, actor: actor, module_key: 'crm', segment_id: foreign_segment.id)
    expect { query.call(relation, contact_column: :contact_id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'never widens corporate coverage through manual inclusions and a broad incoming account relation' do
    issuer = account.master_companies.create!(name: 'Hidden operator', relationship_type: 'internal')
    account.jrc_crm_business_units.create!(name: 'Hidden unit', code: 'MOD-SEG-A', company_id: issuer.id)
    internal_person = create(:contact, account: account, company_id: issuer.id)
    hidden = account.jrc_crm_leads.create!(name: 'Hidden operator lead', owner: actor, contact: internal_person)
    JrcCustomers::SegmentOverride.create!(account: account, taxonomy: taxonomy, company: issuer, mode: 'include')
    JrcCustomers::SegmentOverride.create!(account: account, taxonomy: taxonomy, contact: internal_person, mode: 'include')
    expect(filter.call(relation, company_column: :company_id, contact_column: :contact_id).pluck(:id)).not_to include(hidden.id)
  end

  it 'requires current directory feature, current membership and custom-role permission only for the selected filter' do
    account.disable_features!('jrc_customer_master')
    expect { filter.call(relation, contact_column: :contact_id) }.to raise_error(Pundit::NotAuthorizedError)
    account.enable_features!('jrc_customer_master')
    role = create(:custom_role, account: account, permissions: ['jrc_crm'])
    account.account_users.find_by!(user: actor).update!(role: :agent, custom_role: role)
    expect { filter.call(relation, contact_column: :contact_id) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rejects malformed identifiers and unsupported programmer configurations rather than silently ignoring the filter' do
    [[], {}, true, '0', '-1', '1 OR 1=1', '9223372036854775808'].each do |id|
      query = described_class.new(account: account, actor: actor, module_key: 'crm', segment_id: id)
      expect { query.call(relation, contact_column: :contact_id) }.to raise_error(ActionController::BadRequest)
    end
    expect { described_class.new(account: account, actor: actor, module_key: 'invalid', segment_id: nil) }.to raise_error(ArgumentError)
    expect { filter.call(relation) }.to raise_error(ArgumentError)
  end
end

require 'rails_helper'

RSpec.describe JrcCustomers::SubjectSources do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:company) { account.master_companies.create!(name: 'Synthetic subject company') }
  let(:contact) { create(:contact, account: account, company_id: company.id) }
  let(:sources) { described_class.new(account: account, user: actor, account_user: member, company: company) }
  let(:full) { JrcCustomers::Customer360.new(account: account, user: actor, account_user: member, company: company) }

  before { account.enable_features!('jrc_customer_master', 'jrc_crm', 'jrc_projects') }

  it 'shares exact company and indirect-contact project predicates with the complete360 without unrelated customers' do
    direct = JrcProjects::Project.create!(account: account, owner: actor, company_id: company.id, key: 'SS_DIRECT', name: 'Company source')
    indirect = JrcProjects::Project.create!(account: account, owner: actor, contact: contact, key: 'SS_CONTACT', name: 'Contact source')
    other = create(:contact, account: account)
    JrcProjects::Project.create!(account: account, owner: actor, contact: other, key: 'SS_OTHER', name: 'Unrelated source')
    expected = [direct.id, indirect.id].sort
    expect(sources.projects.order(:id).pluck(:id)).to eq(expected)
    expect(full.projects.order(:id).pluck(:id)).to eq(expected)
    selected = described_class.new(account: account, user: actor, account_user: member, contact: contact)
    expect(selected.projects.pluck(:id)).to eq([indirect.id])
  end

  it 'preserves direct order and authorized-deal origins instead of dropping orders without a direct contact' do
    pipeline = create(:jrc_crm_pipeline, account: account)
    stage = create(:jrc_crm_stage, account: account, pipeline: pipeline)
    deal = create(:jrc_crm_deal, account: account, owner: actor, company: company, pipeline: pipeline, stage: stage)
    direct = account.jrc_crm_sales_orders.create!(owner: actor, contact: contact, status: 'approved')
    linked = account.jrc_crm_sales_orders.create!(owner: actor, deal: deal, status: 'approved')
    account.jrc_crm_sales_orders.create!(owner: actor, contact: create(:contact, account: account), status: 'approved')
    expected = [direct.id, linked.id].sort
    expect(sources.orders.order(:id).pluck(:id)).to eq(expected)
    expect(full.orders.order(:id).pluck(:id)).to eq(expected)
    expect([sources.deals.pluck(:id), full.deals.pluck(:id)]).to eq([[deal.id], [deal.id]])
  end

  it 'retains native CRM ownership and does not expose another owner order for the same customer' do
    agent = create(:user, account: account, role: :agent)
    membership = account.account_users.find_by!(user: agent)
    role = create(:custom_role, account: account, permissions: %w[contact_manage jrc_crm])
    membership.update!(custom_role: role)
    visible = account.jrc_crm_sales_orders.create!(owner: agent, contact: contact, status: 'approved')
    account.jrc_crm_sales_orders.create!(owner: actor, contact: contact, status: 'approved')
    selected = described_class.new(account: account, user: agent, account_user: membership, contact: contact)
    expect(selected.orders.pluck(:id)).to eq([visible.id])
    expect(selected.projects).not_to exist
  end

  it 'preserves native private-project and module grants rather than treating contact matching as authorization' do
    agent = create(:user, account: account, role: :agent)
    membership = account.account_users.find_by!(user: agent)
    role = create(:custom_role, account: account, permissions: %w[contact_manage jrc_projects_project_view])
    membership.update!(custom_role: role, jrc_projects_enabled: true)
    visible = JrcProjects::Project.create!(account: account, owner: agent, contact: contact,
                                           key: 'SS_OWN', name: 'Own native source', visibility: 'private')
    JrcProjects::Project.create!(account: account, owner: actor, contact: contact,
                                 key: 'SS_PRIVATE', name: 'Other private native source', visibility: 'private')
    selected = described_class.new(account: account, user: agent, account_user: membership, contact: contact)
    expect(selected.projects.pluck(:id)).to eq([visible.id])
    expect(selected.orders).not_to exist
  end

  it 'reuses native operator and unit coverage for CRM orders even when both orders have the same customer' do
    issuer = account.master_companies.create!(name: 'Synthetic issuer', relationship_type: 'internal')
    units = Array.new(2) do |index|
      account.jrc_crm_business_units.create!(operating_company: issuer, name: "Synthetic unit #{index}", code: SecureRandom.hex(5))
    end
    account.jrc_crm_user_business_units.create!(user: actor, company: issuer, business_unit: units.first,
                                                scope: 'BUSINESS_UNIT', active: true, structure_managed: true)
    visible = account.jrc_crm_sales_orders.create!(owner: actor, contact: contact, business_unit: units.first, status: 'approved')
    account.jrc_crm_sales_orders.create!(owner: actor, contact: contact, business_unit: units.last, status: 'approved')
    selected = described_class.new(account: account, user: actor, account_user: member, contact: contact)
    expect(selected.orders.pluck(:id)).to eq([visible.id])
  end

  it 'denies foreign subjects and ambiguous roots before constructing their source relations' do
    foreign = create(:contact, account: create(:account))
    expect { described_class.new(account: account, user: actor, account_user: member, contact: foreign) }
      .to raise_error(ActiveRecord::RecordNotFound)
    expect { described_class.new(account: account, user: actor, account_user: member, company: company, contact: contact) }
      .to raise_error(ArgumentError)
    expect { described_class.new(account: account, user: actor, account_user: member) }.to raise_error(ArgumentError)
  end
end

require 'rails_helper'

RSpec.describe JrcCrm::CorporateCoverage do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:company) { account.master_companies.create!(name: 'Synthetic issuer', relationship_type: 'internal') }
  let(:unit) { account.jrc_crm_business_units.create!(name: 'Synthetic unit', code: 'synthetic', company_id: company.id) }
  let(:contact) { create(:contact, account: account) }
  let(:coverage) { described_class.new(account: account, user: user) }

  before do
    unit
    JrcCrm::UserBusinessUnit.create!(account: account, user: user, scope: 'COMPANY', company: company, structure_managed: true)
  end

  it 'hides financial documents with unknown issuer from company-only coverage' do
    unknown = account.jrc_crm_proposals.create!(owner: user, contact: contact, title: 'Unknown synthetic issuer')
    known = account.jrc_crm_proposals.create!(owner: user, contact: contact, business_unit: unit, title: 'Known synthetic issuer')
    expect(coverage.restrict(account.jrc_crm_proposals).pluck(:id)).to eq([known.id])
    expect(coverage.restrict(account.jrc_crm_proposals).exists?(unknown.id)).to be(false)
  end

  it 'permits explicit corporate review of unknown issuer but blocks commercial effects until mapped' do
    JrcCrm::UserBusinessUnit.create!(account: account, user: user, scope: 'GROUP', structure_managed: true)
    unknown = account.jrc_crm_proposals.create!(owner: user, contact: contact, title: 'Unmapped synthetic issuer')
    expect(coverage.restrict(account.jrc_crm_proposals).exists?(unknown.id)).to be(true)
    expect { JrcApprovals::CommercialGate.check!(resource: unknown, user: user, key: 'crm.proposal_send') }
      .to raise_error(JrcApprovals::Error, 'ISSUER_UNIT_REQUIRED')
  end

  it 'cannot widen a relation from a different account' do
    foreign = create(:account).jrc_crm_products.create!(name: 'Foreign synthetic product')
    expect(coverage.restrict(JrcCrm::Product.where(account_id: foreign.account_id))).to be_empty
  end

  it 'keeps an unconfigured tenant on its native legacy path without creating corporate defaults' do
    empty_account = create(:account)
    empty_user = create(:user, account: empty_account, role: :administrator)
    boundary = described_class.new(account: empty_account, user: empty_user)
    expect(boundary).not_to be_configured
    expect(boundary).not_to be_group
    expect(JrcApprovals::CommercialGate.mode(empty_account, 'crm.proposal_send')).to eq('disabled')
    expect(empty_account.master_companies).to be_empty
    expect(empty_account.jrc_crm_business_units).to be_empty
    expect(JrcApprovals::Policy.where(account: empty_account)).to be_empty
    expect(empty_account.reload.custom_attributes).not_to have_key(JrcApprovals::CommercialGate::SETTINGS_KEY)
  end

  it 'does not grant unmapped Service Desk units to company coverage' do
    operator = JrcServiceDesk::OperatorCompany.create!(account: account, name: 'Synthetic operator', code: 'operator')
    sd = JrcServiceDesk::Unit.create!(account: account, operator_company: operator, name: 'Synthetic SD unit', code: 'sd')
    expect(coverage.service_desk_units(JrcServiceDesk::Unit.where(account: account))).to be_empty
    unit.update!(settings: { 'service_desk_unit_id' => sd.id.to_s })
    expect(coverage.service_desk_units(JrcServiceDesk::Unit.where(account: account)).pluck(:id)).to eq([sd.id])
  end

  it 'does not let a company administrator change the corporate authority registry' do
    expect { JrcCrm::OrganizationalStructureService.new(account: account, actor: user).update_settings!(group_name: 'Unauthorized') }
      .to raise_error(Pundit::NotAuthorizedError)
    expect(account.reload.custom_attributes).not_to have_key('jrc_crm_organization')
  end

  it 'bounds company-wide operational queues without granting unassigned or other-company queues' do
    allowed = JrcOperations::Queue.create!(account: account, operating_company: company, name: 'Allowed queue', code: 'allowed')
    foreign = account.master_companies.create!(name: 'Other synthetic issuer', relationship_type: 'internal')
    JrcOperations::Queue.create!(account: account, operating_company: foreign, name: 'Blocked queue', code: 'blocked')
    JrcOperations::Queue.create!(account: account, name: 'Unassigned queue', code: 'unassigned')
    expect(coverage.restrict(JrcOperations::Queue.where(account: account)).pluck(:id)).to eq([allowed.id])
  end

  it 'rejects a queue whose explicit company disagrees with its native unit' do
    foreign = account.master_companies.create!(name: 'Other synthetic issuer', relationship_type: 'internal')
    queue = JrcOperations::Queue.new(account: account, operating_company: foreign, business_unit: unit,
                                     name: 'Incompatible queue', code: 'incompatible')
    expect(queue).not_to be_valid
    expect(queue.errors[:operating_company]).to include('must match business unit')
  end

  it 'does not widen company-wide queues from an explicit unit-only membership' do
    account.jrc_crm_user_business_units.find_by!(user: user).update!(scope: 'BUSINESS_UNIT', business_unit: unit)
    JrcOperations::Queue.create!(account: account, operating_company: company, name: 'Company queue', code: 'company')
    local = JrcOperations::Queue.create!(account: account, operating_company: company, business_unit: unit,
                                         name: 'Unit queue', code: 'unit')
    expect(coverage.restrict(JrcOperations::Queue.where(account: account)).pluck(:id)).to eq([local.id])
  end

  it 'inherits an invoice issuer but rejects a payment whose unit masks an unauthorized invoice' do
    foreign = account.master_companies.create!(name: 'Foreign synthetic issuer', relationship_type: 'internal')
    foreign_unit = account.jrc_crm_business_units.create!(name: 'Foreign unit', code: 'foreign', company_id: foreign.id)
    own_invoice = account.jrc_crm_invoices.create!(business_unit: unit, due_on: Date.current, total_cents: 1000)
    other_invoice = account.jrc_crm_invoices.create!(business_unit: foreign_unit, due_on: Date.current, total_cents: 1000)
    allowed = account.jrc_crm_payments.create!(invoice: own_invoice, paid_at: Time.current, amount_cents: 100)
    account.jrc_crm_payments.create!(invoice: other_invoice, business_unit: unit, paid_at: Time.current, amount_cents: 100)
    expect(coverage.restrict(account.jrc_crm_payments).pluck(:id)).to eq([allowed.id])
  end
end

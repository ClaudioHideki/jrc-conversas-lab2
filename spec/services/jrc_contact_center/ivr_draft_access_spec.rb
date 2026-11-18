require 'rails_helper'

RSpec.describe JrcContactCenter::IvrDraftAccess do
  let(:account) { create(:account) }
  let(:operator) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: operator) }
  let(:context) { { account: account, account_user: member, user: operator } }
  let(:company) { JrcCustomers::Company.create!(account: account, name: 'SYNTHETIC own issuer', relationship_type: 'internal', active: true) }
  let(:business_unit) do
    JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: 'SYNTHETIC own business', code: 'OWN', active: true)
  end
  let(:other_company) { JrcCustomers::Company.create!(account: account, name: 'SYNTHETIC other issuer', relationship_type: 'internal', active: true) }
  let(:other_business) do
    JrcCrm::BusinessUnit.create!(account: account, operating_company: other_company, name: 'SYNTHETIC other business', code: 'OTHER', active: true)
  end
  let(:unit) do
    JrcContactCenter::Unit.create!(account: account, code: 'LOCAL', name: 'SYNTHETIC operational', kind: 'sac',
                                   settings: { 'issuer_company_id' => company.id, 'business_unit_id' => business_unit.id })
  end
  let(:definition) { { 'schema_version' => 1, 'start' => 'end', 'nodes' => [{ 'id' => 'end', 'type' => 'end' }] } }
  let(:values) { { name: 'SYNTHETIC draft', status: 'draft', definition: definition, request_id: SecureRandom.uuid, expected_revision: 0 } }
  let(:writer) { JrcContactCenter::IvrDraftWrite.new(context: context) }
  let(:draft) { writer.call(input: JrcContactCenter::IvrDraftInput.new(**values), unit_id: unit.id).fetch(:draft) }

  before do
    account.enable_features!('jrc_contact_center')
    JrcCrm::UserBusinessUnit.create!(account: account, user: operator, scope: 'GROUP', active: true, structure_managed: true)
  end

  it 'lets an explicitly covered native administrator read a draft only in the current and historical authorized unit' do
    draft
    JrcCrm::UserBusinessUnit.find_by!(account: account, user: operator).update!(scope: 'BUSINESS_UNIT', company_id: company.id,
                                                                                business_unit_id: business_unit.id)
    expect(described_class.new(context: context).find!(draft.id)).to eq(draft)
    expect(JrcContactCenter::ModulePolicy.new(context, :contact_center).administer?).to be(false)
  end

  it 'does not transfer access to old artifacts when an operational unit is remapped into another issuer' do
    draft
    unit.update!(settings: { 'issuer_company_id' => other_company.id, 'business_unit_id' => other_business.id })
    JrcCrm::UserBusinessUnit.find_by!(account: account, user: operator).update!(scope: 'BUSINESS_UNIT', company_id: other_company.id,
                                                                                business_unit_id: other_business.id)
    expect do
      described_class.new(context: context).find!(draft.id)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'does not retain access from a historical scope after current unit access is lost' do
    draft
    JrcCrm::UserBusinessUnit.find_by!(account: account, user: operator).update!(scope: 'BUSINESS_UNIT', company_id: company.id,
                                                                                business_unit_id: business_unit.id)
    unit.update!(settings: { 'issuer_company_id' => other_company.id, 'business_unit_id' => other_business.id })
    expect { described_class.new(context: context).find!(draft.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'does not reactivate legacy unscoped access to a previously corporate artifact if the structure is removed' do
    draft
    unit.update!(settings: {})
    JrcCrm::UserBusinessUnit.where(account: account).delete_all
    JrcCrm::BusinessUnit.where(account: account).delete_all
    expect(JrcCrm::CorporateCoverage.new(account: account, user: operator).configured?).to be(false)
    expect { described_class.new(context: context).find!(draft.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'preserves Group access within the account while requiring a new identity after corporate remapping' do
    draft
    unit.update!(settings: { 'issuer_company_id' => other_company.id, 'business_unit_id' => other_business.id })
    expect(described_class.new(context: context).find!(draft.id)).to eq(draft)
    input = JrcContactCenter::IvrDraftInput.new(**values, expected_revision: 1, request_id: SecureRandom.uuid)
    expect { writer.call(input: input, id: draft.id) }.to raise_error(JrcContactCenter::OperationError, 'ivr_scope_changed')
    expect(draft.versions.count).to eq(1)
  end

  it 'allows local archival without changing the historical scope after corporate remapping' do
    before = draft.scope_snapshot
    unit.update!(settings: { 'issuer_company_id' => other_company.id, 'business_unit_id' => other_business.id })
    archive = JrcContactCenter::IvrDraftInput.new(**values, status: 'archived', expected_revision: 1, request_id: SecureRandom.uuid)
    expect(writer.call(input: archive, id: draft.id)[:version].status).to eq('archived')
    expect(draft.reload.scope_snapshot).to eq(before)
  end

  it 'does not invalidate historical reads when the reference is inactive but still authorized' do
    draft
    unit.update!(status: 'inactive')
    expect(described_class.new(context: context).find!(draft.id)).to eq(draft)
    input = JrcContactCenter::IvrDraftInput.new(**values, expected_revision: 1, request_id: SecureRandom.uuid)
    expect { writer.call(input: input, id: draft.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'checks explicit individual eligibility even for a corporate Group actor' do
    draft
    JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(eligible: false)
    expect { described_class.new(context: context).find!(draft.id) }.to raise_error(Pundit::NotAuthorizedError)
  end
end

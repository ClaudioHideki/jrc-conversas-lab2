require 'rails_helper'

RSpec.describe JrcRelationship::AssignmentCreation do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:context) { JrcRelationship::Context.new(member) }
  let(:company) { account.master_companies.create!(name: 'Synthetic native allocation customer') }
  let(:service) { described_class.new(context) }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'validates an unsaved native proposal with the actual source policy without inserting, allocating a sequence or recording an audit' do
    company
    creator = service
    statements = []
    original = [JrcRelationship::Assignment.count, JrcCrm::AuditEvent.count]
    subscriber = ->(_name, _start, _finish, _id, payload) { statements << payload.fetch(:sql) }
    record = ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      creator.preview({ 'company_id' => company.id, 'owner_id' => actor.id })
    end
    expect(record).to be_new_record
    expect(record.id).to be_nil
    expect([JrcRelationship::Assignment.count, JrcCrm::AuditEvent.count]).to eq(original)
    expect(statements.grep(/\b(?:INSERT|UPDATE|DELETE|nextval)\b/i)).to be_empty
    expect(statements.grep(/jsonb_populate_record/)).not_to be_empty
  end

  it 'denies a proposed allocation outside the native issuer and unit scope before any insert' do
    issuer = account.master_companies.create!(name: 'Synthetic preview issuer', relationship_type: 'internal')
    units = Array.new(2) do |index|
      account.jrc_crm_business_units.create!(name: "Synthetic preview unit #{index}", code: SecureRandom.hex(6), operating_company: issuer)
    end
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: issuer,
                                                business_unit: units.first, active: true, structure_managed: true)
    expect do
      service.preview({ 'company_id' => company.id, 'owner_id' => actor.id, 'business_unit_id' => units.last.id })
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcRelationship::Assignment.where(account: account)).to be_empty
  end

  it 'reuses an existing master company through its authorized contact and audits native creation without duplicating the directory' do
    contact = create(:contact, account: account, company_id: company.id)
    expect do
      record = service.call({ 'contact_id' => contact.id, 'owner_id' => actor.id.to_s })
      expect(record).to have_attributes(account_id: account.id, company_id: company.id, contact_id: nil, owner_id: actor.id)
      expect(JrcCrm::AuditEvent.where(account: account, resource_id: record.id)
               .where("metadata ->> 'action' = 'assignment_created'")).to exist
    end.not_to change(JrcCustomers::Company, :count)
  end

  it 'rechecks native manage authority after the captured context loses its grant and leaves no allocation or audit' do
    creator = service
    role = account.custom_roles.create!(name: 'Synthetic former manager', permissions: %w[contact_manage jrc_relationship_view jrc_relationship_team])
    member.update!(role: :agent, custom_role: role)
    company
    original = [JrcRelationship::Assignment.count, JrcCrm::AuditEvent.count]
    expect do
      creator.call({ 'company_id' => company.id, 'owner_id' => actor.id })
    end.to raise_error(Pundit::NotAuthorizedError)
    expect([JrcRelationship::Assignment.count, JrcCrm::AuditEvent.count]).to eq(original)
  end

  it 'rejects account and actor fields rather than taking authority from a reusable caller payload' do
    expect do
      service.call({ 'company_id' => company.id, 'account_id' => create(:account).id, 'actor_id' => actor.id })
    end.to raise_error(ArgumentError, 'Unsupported allocation fields')
    expect(JrcRelationship::Assignment.where(account: account)).to be_empty
  end

  it 'rejects a foreign master company and rolls back allocation and audit together' do
    foreign = create(:account).master_companies.create!(name: 'Synthetic foreign master company')
    original = [JrcRelationship::Assignment.count, JrcCrm::AuditEvent.count]
    expect do
      service.call({ 'company_id' => foreign.id, 'owner_id' => actor.id })
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect([JrcRelationship::Assignment.count, JrcCrm::AuditEvent.count]).to eq(original)
  end

  it 'requires fresh native destination membership rather than accepting another accounts owner ID' do
    outsider = create(:user, account: create(:account), role: :administrator)
    expect do
      service.call({ 'company_id' => company.id, 'owner_id' => outsider.id })
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcRelationship::Assignment.where(account: account)).to be_empty
  end

  it 'keeps organizational unit coverage restrictive and rolls back an otherwise valid native allocation' do
    issuer = account.master_companies.create!(name: 'Synthetic native allocation operator', relationship_type: 'internal')
    units = Array.new(2) do |index|
      account.jrc_crm_business_units.create!(name: "Synthetic allocation unit #{index}", code: SecureRandom.hex(6), operating_company: issuer)
    end
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: issuer,
                                                business_unit: units.first, active: true, structure_managed: true)
    company
    original = [JrcRelationship::Assignment.count, JrcCrm::AuditEvent.count]
    expect do
      service.call({ 'company_id' => company.id, 'owner_id' => actor.id, 'business_unit_id' => units.last.id })
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect([JrcRelationship::Assignment.count, JrcCrm::AuditEvent.count]).to eq(original)
  end

  it 'preserves onboarding admission and typed workload inputs from native configuration' do
    JrcRelationship::Configuration.create!(account: account, rules: { 'handoff_acceptance_required' => true })
    record = service.call({ 'company_id' => company.id, 'owner_id' => actor.id,
                            'settings' => { 'capacity_workload' => { 'hours' => 2.5 } } })
    expect(record).to have_attributes(status: 'onboarding', company_id: company.id, owner_id: actor.id)
    expect(record.settings).to eq('capacity_workload' => { 'hours' => 2.5 })
  end

  it 'does not accept caller-forged commercial exception metadata through nested settings' do
    expect do
      service.call({ 'company_id' => company.id, 'owner_id' => actor.id,
                     'settings' => { 'eligibility_exception' => { 'approved_by_id' => actor.id, 'reason' => 'Untrusted input' } } })
    end.to raise_error(ArgumentError, 'Unsupported allocation settings')
    expect(JrcRelationship::Assignment.where(account: account)).to be_empty
  end

  it 'retains the native configured capacity admission before any root or creation audit is committed' do
    JrcRelationship::Configuration.create!(account: account, rules: { 'portfolio_capacity_limits' => [
                                             { 'user_id' => actor.id, 'maximum' => 0, 'availability' => 1, 'dedication' => 1 }
                                           ] })
    company
    original = [JrcRelationship::Assignment.count, JrcCrm::AuditEvent.count]
    expect do
      service.call({ 'company_id' => company.id, 'owner_id' => actor.id })
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect([JrcRelationship::Assignment.count, JrcCrm::AuditEvent.count]).to eq(original)
  end
end

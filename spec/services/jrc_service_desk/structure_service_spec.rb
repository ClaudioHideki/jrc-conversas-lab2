# frozen_string_literal: true
require 'rails_helper'

RSpec.describe JrcServiceDesk::StructureService do
  include_context 'JRC Service Desk domain'
  let(:keys) { %w[structure_view operator_companies_manage units_manage unit_memberships_manage] }
  let(:role) { create(:custom_role, account: sd_account, permissions: keys.map { |k| "jrc_service_desk_#{k}" }) }
  let(:service) { described_class.new(user_context: sd_context) }
  before do
    skip 'Native CustomRole unavailable - pending' unless defined?(CustomRole)
    sd_account_user.update!(role: :administrator, custom_role: role)
  end

  it 'permits explicitly delegated structure without granting operations' do
    sd_membership.update!(active: false)
    expect(JrcServiceDesk::StructureContext.new(sd_context).available?).to be(true)
    expect(JrcServiceDesk::OperationalContext.new(sd_context).native_operator?).to be(false)
    result = service.create(resource: 'operator_companies', attributes: { name: 'New operator', code: 'new', active: true }, reason: 'CHG-1', idempotency_key: 'o1')
    expect(result.record.account_id).to eq(sd_account.id)
    expect(sd_membership.reload.active?).to be(false)
    expect(Audited::Audit.find(result.audit_id).user_id).to eq(sd_user.id)
    repeat = service.create(resource: 'operator_companies', attributes: { name: 'New operator', code: 'new', active: true }, reason: 'CHG-1', idempotency_key: 'o1')
    expect(repeat.record.id).to eq(result.record.id)
  end

  it 'permits native administrators to manage structure without a CustomRole' do
    sd_account_user.update!(custom_role: nil)
    result = service.create(resource: 'operator_companies', attributes: { name: 'X', code: 'x', active: true }, reason: 'CHG-1', idempotency_key: 'x')
    expect(result.record.account_id).to eq(sd_account.id)
    expect(sd_account_user.reload.custom_role_id).to be_nil
    expect(sd_account_user.role).to eq('administrator')
  end

  it 'denies agents with a membership but no structural capability' do
    sd_account_user.update!(role: :agent, custom_role: nil)
    expect { service.create(resource: 'operator_companies', attributes: { name: 'X', code: 'x', active: true }, reason: 'CHG-1', idempotency_key: 'x') }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'denies foreign unit/operator/member references and ownership mutation' do
    expect { service.create(resource: 'units', attributes: { name: 'X', code: 'x', active: true, operator_company_id: sd_foreign_operator.id }, reason: 'CHG-1', idempotency_key: 'x') }.to raise_error(ActiveRecord::RecordNotFound)
    other = create(:account_user, account: sd_foreign_account)
    expect { service.create(resource: 'unit_memberships', attributes: { active: true, unit_id: sd_unit.id, account_user_id: other.id }, reason: 'CHG-1', idempotency_key: 'y') }.to raise_error(ActiveRecord::RecordNotFound)
    expect { service.update(resource: 'units', record_id: sd_unit.id, attributes: { account_id: sd_foreign_account.id }, reason: 'CHG-1', idempotency_key: 'z', expected_revision: 'a' * 64) }.to raise_error(ArgumentError)
  end

  it 'prevents self-grant, permits explicit self-revocation, and refuses stale revisions' do
    revision = JrcServiceDesk::StructureRecords.revision('unit_memberships', sd_membership)
    result = service.update(resource: 'unit_memberships', record_id: sd_membership.id, attributes: { active: false }, reason: 'CHG-1', idempotency_key: 'revoke', expected_revision: revision)
    expect(result.record.active?).to be(false)
    expect { service.update(resource: 'unit_memberships', record_id: sd_membership.id, attributes: { active: true }, reason: 'CHG-1', idempotency_key: 'grant', expected_revision: JrcServiceDesk::StructureRecords.revision('unit_memberships', sd_membership.reload)) }.to raise_error(Pundit::NotAuthorizedError)
    expect { service.update(resource: 'unit_memberships', record_id: sd_membership.id, attributes: { active: false }, reason: 'CHG-2', idempotency_key: 'stale', expected_revision: revision) }.to raise_error(ActiveRecord::StaleObjectError)
  end

  it 'grants a different client only through the explicit command and never creates its roles' do
    user = create(:user); target = create(:account_user, account: sd_account, user: user, role: :agent)
    result = service.create(resource: 'unit_memberships', attributes: { unit_id: sd_other_unit.id, account_user_id: target.id, active: true }, reason: 'CHG-2', idempotency_key: 'client-grant')
    expect(result.record).to have_attributes(unit_id: sd_other_unit.id, account_user_id: target.id, active: true)
    expect(target.reload.role).to eq('agent'); expect(target.custom_role_id).to be_nil
    expect(JrcServiceDesk::UnitMembership.where(unit_id: sd_other_unit.id, account_user_id: sd_account_user.id)).to be_empty
  end

  it 'immediately denies a revoked structural capability or disabled feature' do
    role.update!(permissions: ['jrc_service_desk_structure_view'])
    expect { service.update(resource: 'units', record_id: sd_unit.id, attributes: { name: 'X' }, reason: 'CHG-3', idempotency_key: 'x', expected_revision: JrcServiceDesk::StructureRecords.revision('units', sd_unit)) }.to raise_error(Pundit::NotAuthorizedError)
    sd_account.disable_features!('jrc_service_desk')
    expect(JrcServiceDesk::StructureContext.new(sd_context).available?).to be(false)
  end
end

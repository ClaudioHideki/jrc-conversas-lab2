# frozen_string_literal: true
require 'rails_helper'

RSpec.describe JrcServiceDesk::InitializeAccountService do
  let(:account) { create(:account) }
  let(:staff) { create(:super_admin) }
  let(:client) { create(:user) }
  let(:au) { create(:account_user, account: account, user: client, role: :administrator) }
  let(:command) { described_class.new(account: account, actor: staff) }
  let(:input) { { operator: { code: 'real-operator', name: 'Selected operator', active: true },
    unit: { code: 'real-unit', name: 'Selected unit', active: true }, account_user_id: au.id,
    confirmed: true, reason: 'Approved request TEST-42' } }
  before do
    account.enable_features!('jrc_service_desk')
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with(JrcServiceDesk::InitializerAuthority::CONFIG_KEY, '').and_return(staff.id.to_s)
  end

  it 'requires a named human and performs the explicit atomic sequence without assigning the actor' do
    au; staff
    before_users = User.count; before_accounts = AccountUser.count
    audit_id = command.call(input: input, idempotency_key: 'first-human-request')
    receipt = command.receipt(audit_id)
    grant = JrcServiceDesk::UnitMembership.find(receipt['membership_id'])
    expect(grant).to have_attributes(account_id: account.id, account_user_id: au.id, active: true)
    expect(grant.unit.operator_company.account_id).to eq(account.id)
    expect(AccountUser.where(account_id: account.id, user_id: staff.id)).to be_empty
    expect(User.count).to eq(before_users); expect(AccountUser.count).to eq(before_accounts)
    expect(Audited::Audit.find(audit_id).user_id).to eq(staff.id)
    expect(receipt['records']).to eq(receipt['current_records'])
    expect(command.empty?).to be(false)
    expect(command.call(input: input, idempotency_key: 'first-human-request')).to eq(audit_id)
    expect(JrcServiceDesk::Unit.where(account_id: account.id).count).to eq(1)
    expect { command.call(input: input, idempotency_key: 'different') }.to raise_error(JrcServiceDesk::IdempotencyConflict)
  end

  it 'never grants native operational scope to the initializing employee' do
    command.call(input: input, idempotency_key: 'one')
    operator_context = { account: account, user: staff, account_user: nil }
    expect(JrcServiceDesk::OperationalContext.new(operator_context).native_operator?).to be(false)
    expect(JrcServiceDesk::TicketPolicy::Scope.new(operator_context, JrcServiceDesk::Ticket).resolve).to be_empty
  end

  it 'denies a normal administrator, undesignated staff, revoked designation and disabled flag' do
    expect { described_class.new(account: account, actor: client).call(input: input, idempotency_key: 'x') }.to raise_error(Pundit::NotAuthorizedError)
    another = create(:super_admin)
    expect { described_class.new(account: account, actor: another).call(input: input, idempotency_key: 'x') }.to raise_error(Pundit::NotAuthorizedError)
    allow(ENV).to receive(:fetch).with(JrcServiceDesk::InitializerAuthority::CONFIG_KEY, '').and_return('')
    expect { command.call(input: input, idempotency_key: 'x') }.to raise_error(Pundit::NotAuthorizedError)
    allow(ENV).to receive(:fetch).with(JrcServiceDesk::InitializerAuthority::CONFIG_KEY, '').and_return(staff.id.to_s)
    account.disable_features!('jrc_service_desk')
    expect { command.call(input: input, idempotency_key: 'x') }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rejects self-grants and grants to other staff without creating partial structure' do
    self_au = create(:account_user, account: account, user: staff, role: :administrator)
    expect { command.call(input: input.merge(account_user_id: self_au.id), idempotency_key: 'self') }.to raise_error(Pundit::NotAuthorizedError)
    other_staff = create(:super_admin)
    target = create(:account_user, account: account, user: other_staff)
    expect { command.call(input: input.merge(account_user_id: target.id), idempotency_key: 'staff') }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcServiceDesk::OperatorCompany.where(account_id: account.id)).to be_empty
  end

  it 'rejects a foreign AccountUser and input ownership/permission manipulation' do
    other = create(:account_user)
    expect { command.call(input: input.merge(account_user_id: other.id), idempotency_key: 'foreign') }.to raise_error(ActiveRecord::RecordNotFound)
    expect { command.call(input: input.merge(account_id: other.account_id), idempotency_key: 'bad') }.to raise_error(ArgumentError)
    expect { command.call(input: input.merge(confirmed: false), idempotency_key: 'bad') }.to raise_error(ArgumentError)
    expect(JrcServiceDesk::Unit.where(account_id: account.id)).to be_empty
  end

  it 'rolls everything back when the native audit cannot be persisted' do
    allow(Audited::Audit).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Audited::Audit.new))
    expect { command.call(input: input, idempotency_key: 'audit-failure') }.to raise_error(ActiveRecord::RecordInvalid)
    [JrcServiceDesk::OperatorCompany, JrcServiceDesk::Unit, JrcServiceDesk::UnitMembership].each do |model|
      expect(model.where(account_id: account.id)).to be_empty
    end
  end

  it 'refuses to reset or merge a partially configured Account' do
    create(:jrc_sd_operator_company, account: account)
    expect { command.call(input: input, idempotency_key: 'existing') }.to raise_error(JrcServiceDesk::IdempotencyConflict)
    expect(JrcServiceDesk::Unit.where(account_id: account.id)).to be_empty
  end
end

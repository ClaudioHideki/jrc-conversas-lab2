require 'rails_helper'

RSpec.describe JrcCustomers::ImportAccess do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:access) { described_class.new(account: account, actor: actor) }

  before { account.enable_features!('jrc_customer_master') }

  it 'retains the company administration gate and offers all import types to an active administrator' do
    expect(access.available_kinds).to eq(%w[companies contacts both])
    expect(access.authorize!(kind: 'both')).to be(true)
  end

  it 'retains the native Enterprise bulk-contact permission without granting company imports' do
    role = create(:custom_role, account: account, permissions: ['contact_manage'])
    AccountUser.find_by!(account: account, user: actor).update!(role: :agent, custom_role: role)
    expect(access.available_kinds).to eq(['contacts'])
    expect(access.authorize!(kind: 'contacts')).to be(true)
    expect { access.authorize!(kind: 'companies') }.to raise_error(Pundit::NotAuthorizedError)
    expect { access.authorize!(kind: 'both') }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'does not confuse ordinary contact editing with permission to import in bulk' do
    AccountUser.find_by!(account: account, user: actor).update!(role: :agent)
    expect(JrcCustomers::ContactDirectory.new(account: account, actor: actor).authorize!).to be_nil
    expect(access.available_kinds).to be_empty
    expect { access.authorize!(kind: 'contacts') }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rechecks a revoked custom permission on the same service instance' do
    role = create(:custom_role, account: account, permissions: ['contact_manage'])
    AccountUser.find_by!(account: account, user: actor).update!(role: :agent, custom_role: role)
    expect(access.authorize!(kind: 'contacts')).to be(true)
    role.update!(permissions: ['conversation_manage'])
    expect { access.authorize!(kind: 'contacts') }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rejects revoked membership and cannot use an administrator identity from another account' do
    expect(access.authorize!(kind: 'companies')).to be(true)
    AccountUser.find_by!(account: account, user: actor).destroy!
    expect { access.authorize!(kind: 'companies') }.to raise_error(Pundit::NotAuthorizedError)
    other = create(:account)
    expect { described_class.new(account: other, actor: actor).authorize!(kind: 'contacts') }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'requires the master feature and an active account on every call' do
    expect(access.authorize!(kind: 'contacts')).to be(true)
    account.disable_features!('jrc_customer_master')
    expect { access.authorize!(kind: 'contacts') }.to raise_error(Pundit::NotAuthorizedError)
    account.enable_features!('jrc_customer_master')
    account.update!(status: :suspended)
    expect { access.authorize!(kind: 'contacts') }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'refuses unsupported destinations rather than interpreting them as a permitted import type' do
    expect { access.authorize!(kind: 'users') }.to raise_error(JrcCustomers::ImportFile::InvalidFile)
    expect { access.authorize!(kind: 'companies,contacts') }.to raise_error(JrcCustomers::ImportFile::InvalidFile)
  end
end

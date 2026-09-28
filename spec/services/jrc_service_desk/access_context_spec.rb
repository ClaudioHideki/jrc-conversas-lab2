# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk::AccessContext do
  subject(:context) { described_class.new(user_context) }

  let(:account) { instance_double(Account, id: 11, persisted?: true, active?: true) }
  let(:user) { instance_double(User, id: 21, persisted?: true) }
  let(:membership) { instance_double(AccountUser, account_id: 11, user_id: 21, persisted?: true) }
  let(:user_context) { { account: account, user: user, account_user: membership } }
  let(:record) { instance_double(Contact, account_id: 11) }

  before do
    allow(account).to receive(:feature_enabled?).with('jrc_service_desk').and_return(true)
  end

  it 'recognizes the native account membership when the flag is enabled' do
    expect(context.available?).to be(true)
  end

  %i[account user account_user].each do |key|
    it "denies a context without #{key}" do
      user_context[key] = nil
      expect(context.available?).to be(false)
    end
  end

  it 'denies when the flag is disabled' do
    allow(account).to receive(:feature_enabled?).with('jrc_service_desk').and_return(false)
    expect(context.available?).to be(false)
  end

  it 'does not cache a successful feature check after it is disabled' do
    expect(context.available?).to be(true)
    allow(account).to receive(:feature_enabled?).with('jrc_service_desk').and_return(false)
    expect(context.available?).to be(false)
  end

  it 'does not coerce a truthy configuration value into permission' do
    allow(account).to receive(:feature_enabled?).with('jrc_service_desk').and_return('true')
    expect(context.available?).to be(false)
  end

  it 'denies a suspended account' do
    allow(account).to receive(:active?).and_return(false)
    expect(context.available?).to be(false)
  end

  %i[account user account_user].each do |key|
    it "denies an unpersisted #{key}" do
      allow(user_context.fetch(key)).to receive(:persisted?).and_return(false)
      expect(context.available?).to be(false)
    end
  end

  it 'denies a membership from another account' do
    allow(membership).to receive(:account_id).and_return(12)
    expect(context.available?).to be(false)
  end

  it 'denies a membership for another user' do
    allow(membership).to receive(:user_id).and_return(22)
    expect(context.available?).to be(false)
  end

  it 'does not silently coerce account identifiers' do
    allow(membership).to receive(:account_id).and_return('11')
    expect(context.available?).to be(false)
  end

  %i[account user].each do |key|
    it "denies a missing #{key} identifier" do
      allow(user_context.fetch(key)).to receive(:id).and_return(nil)
      expect(context.available?).to be(false)
    end
  end

  it 'recognizes a record in the current account without granting an action' do
    expect(context.record_in_account?(record)).to be(true)
  end

  it 'rejects a record in another account' do
    allow(record).to receive(:account_id).and_return(12)
    expect(context.record_in_account?(record)).to be(false)
  end

  it 'rejects a nil record or a record without an account boundary' do
    expect(context.record_in_account?(nil)).to be(false)
    expect(context.record_in_account?(Object.new)).to be(false)
  end

  it 'rejects a record with no account identifier' do
    allow(record).to receive(:account_id).and_return(nil)
    expect(context.record_in_account?(record)).to be(false)
  end

  it 'rejects record access when the flag is disabled' do
    allow(account).to receive(:feature_enabled?).with('jrc_service_desk').and_return(false)
    expect(context.record_in_account?(record)).to be(false)
  end

  it 'does not conceal an invalid feature registry' do
    allow(account).to receive(:feature_enabled?).and_raise(NoMethodError, 'invalid flag configuration')
    expect { context.available? }.to raise_error(NoMethodError)
  end
end

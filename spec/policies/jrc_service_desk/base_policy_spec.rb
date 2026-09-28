# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk::BasePolicy do
  let(:account) { instance_double(Account, id: 11, persisted?: true, active?: true) }
  let(:user) { instance_double(User, id: 21, persisted?: true) }
  let(:membership) { instance_double(AccountUser, account_id: 11, user_id: 21, persisted?: true, administrator?: true) }
  let(:context) { { account: account, user: user, account_user: membership } }
  let(:record) { instance_double(Contact, account_id: 11) }
  let(:relation) { instance_double(ActiveRecord::Relation) }
  let(:empty_relation) { instance_double(ActiveRecord::Relation) }

  before do
    allow(account).to receive(:feature_enabled?).with('jrc_service_desk').and_return(true)
    allow(relation).to receive(:none).and_return(empty_relation)
  end

  %i[index? show? create? new? update? edit? destroy?].each do |action|
    it "denies #{action} even for an administrator with the flag enabled" do
      expect(described_class.new(context, record).public_send(action)).to be(false)
    end
  end

  it 'denies an administrator from another account' do
    allow(record).to receive(:account_id).and_return(12)
    expect(described_class.new(context, record).show?).to be(false)
  end

  it 'denies without an authenticated account context' do
    policy = described_class.new({}, record)
    expect(policy.index?).to be(false)
    expect(policy.show?).to be(false)
  end

  it 'resolves to no records even when the account prerequisite is satisfied' do
    expect(relation).not_to receive(:where)
    expect(described_class::Scope.new(context, relation).resolve).to eq(empty_relation)
  end

  it 'resolves to no records with no context' do
    expect(described_class::Scope.new({}, relation).resolve).to eq(empty_relation)
  end

  context 'when a concrete scope uses the protected account boundary' do
    let(:boundary_scope) do
      Class.new(described_class::Scope) do
        def resolve
          account_scope
        end
      end
    end

    it 'filters by the account from the trusted context' do
      expect(relation).to receive(:where).with(account_id: 11).and_return(empty_relation)
      expect(boundary_scope.new(context, relation).resolve).to eq(empty_relation)
    end

    it 'denies a cross-account membership before querying data' do
      allow(membership).to receive(:account_id).and_return(12)
      expect(relation).not_to receive(:where)
      expect(boundary_scope.new(context, relation).resolve).to eq(empty_relation)
    end

    it 'denies when the feature flag is disabled' do
      allow(account).to receive(:feature_enabled?).with('jrc_service_desk').and_return(false)
      expect(relation).not_to receive(:where)
      expect(boundary_scope.new(context, relation).resolve).to eq(empty_relation)
    end
  end
end

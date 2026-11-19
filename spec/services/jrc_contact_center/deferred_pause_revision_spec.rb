require 'rails_helper'

RSpec.describe JrcContactCenter::DeferredPauseRevision do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account) }
  let(:member) { account.account_users.find_by!(user: actor) }

  it 'provides a stable bounded token before any own request exists' do
    revision = described_class.token(account: account, member: member)
    expect(revision).to match(/\A[0-9a-f]{64}\z/)
    expect(described_class.token(account: account, member: member)).to eq(revision)
    expect(JrcContactCenter::DeferredPauseRequest.where(account: account)).to be_empty
  end

  it 'does not reuse the empty-history revision between two members of the same account' do
    other = create(:user, account: account)
    other_member = account.account_users.find_by!(user: other)
    expect(described_class.token(account: account, member: other_member)).not_to eq(described_class.token(account: account, member: member))
  end

  it 'refuses a member from another account' do
    other_account = create(:account)
    expect do
      described_class.token(account: other_account, member: member)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end
end

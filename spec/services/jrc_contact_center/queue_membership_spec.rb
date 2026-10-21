# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcContactCenter::QueueMembership do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  it 'rejects a membership linking a queue to a user from another account at the database boundary' do
    unit = JrcContactCenter::Unit.create!(account: account, code: 'TEST', name: 'Test', kind: 'sac')
    queue = JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'Q', name: 'Test queue')
    other_agent = create(:user, account: other_account, role: :agent)
    other_member = other_account.account_users.find_by!(user: other_agent)

    expect do
      described_class.transaction(requires_new: true) do
        described_class.create!(account: account, queue: queue, account_user: other_member)
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(described_class.where(account: account)).to be_empty
  end
end

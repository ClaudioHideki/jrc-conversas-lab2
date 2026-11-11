require 'rails_helper'

RSpec.describe ConversationFinder do
  it 'uses an ID tie-breaker so equal activity timestamps remain in deterministic pages' do
    previous_account = Current.account
    account = create(:account)
    admin = create(:user, account: account, role: :administrator)
    inbox = create(:inbox, account: account, enable_auto_assignment: false)
    records = create_list(:conversation, 5, account: account, inbox: inbox)
    # Equal timestamps are the pagination fixture, without creating update callbacks.
    account.conversations.update_all(last_activity_at: Time.utc(2026, 1, 1)) # rubocop:disable Rails/SkipsModelValidations
    expect(account.conversations.sort_on_last_activity_at.to_sql).to include('"conversations"."id" ASC')
    Current.account = account

    with_modified_env(CONVERSATION_RESULTS_PER_PAGE: '2') do
      ids = [1, 2, 3].flat_map do |page|
        described_class.new(admin, { status: 'all', page: page }).perform.fetch(:conversations).pluck(:id)
      end
      expect(ids).to eq(records.map(&:id).sort)
      expect(ids.uniq.size).to eq(5)
    end
  ensure
    Current.account = previous_account
  end
end

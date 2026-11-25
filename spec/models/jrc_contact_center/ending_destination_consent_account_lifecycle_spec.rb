require 'rails_helper'

# Prepared native lifecycle preservation cases, not a new account deletion
# policy. Existing native foreign keys may still block retirement; do not
# remove them, delete business records or erase live history to make it pass.
RSpec.describe JrcContactCenter::EndingDestinationConsent, type: :model do
  include_context 'with native typed ending schema evidence'

  def typed_history_snapshot
    [described_class, JrcContactCenter::EndingDestinationAttempt,
     JrcContactCenter::EndingDestinationExecution, JrcContactCenter::EndingDestinationOutcome].map do |model|
      [model.name, model.where(account: account).order(:id).map(&:attributes)]
    end
  end

  it 'does not add a live user or membership foreign key that can erase immutable actor history' do
    tables = %i[jrc_contact_center_ending_destination_consents jrc_contact_center_ending_destination_attempts
                jrc_contact_center_ending_destination_executions jrc_contact_center_ending_destination_outcomes]
    targets = tables.flat_map { |table| ApplicationRecord.connection.foreign_keys(table).map(&:to_table) }
    expect(targets).not_to include('users', 'account_users')
    expect(targets.count('jrc_contact_center_ending_scope_accounts')).to eq(4)
  end

  it 'preserves native retirement refusal and every typed consent, attempt and outcome' do
    failed_typed_attempt
    before = typed_history_snapshot
    expect do
      Account.transaction(requires_new: true) { account.destroy! }
    end.to raise_error(ActiveRecord::InvalidForeignKey, /jrc_contact_center_/)
    expect(Account.exists?(account.id)).to be true
    expect(typed_history_snapshot).to eq(before)
  end

  it 'cannot erase typed history by deleting its technical scope root while the real account is live' do
    failed_typed_attempt
    before = typed_history_snapshot
    query = "DELETE FROM jrc_contact_center_ending_scope_accounts WHERE account_id = #{Integer(account.id)}"
    expect { guarded_origin_sql(query) }.to raise_error(ActiveRecord::StatementInvalid, /account reference is immutable/)
    expect(typed_history_snapshot).to eq(before)
  end

  it 'leaves populated typed history intact when a different empty synthetic account is actually retired' do
    failed_typed_attempt
    before = typed_history_snapshot
    other = create(:account)
    other_id = other.id
    other.delete
    expect(Account.exists?(other_id)).to be false
    query = "SELECT count(*) FROM jrc_contact_center_ending_scope_accounts WHERE account_id = #{Integer(other_id)}"
    expect(ApplicationRecord.connection.select_value(query).to_i).to eq(0)
    expect(typed_history_snapshot).to eq(before)
  end
end

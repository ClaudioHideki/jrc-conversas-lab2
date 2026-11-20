require 'rails_helper'

RSpec.describe JrcContactCenter::TeamState do
  let(:account) { create(:account) }
  let(:team) { create(:team, account: account) }

  it 'enforces the existing native team account at both the model and composite foreign key' do
    foreign = create(:team, account: create(:account))
    state = described_class.new(account: account, team: foreign, active: false)
    expect(state).not_to be_valid
    expect do
      described_class.transaction(requires_new: true) do
        values = { account_id: account.id, team_id: foreign.id, active: false, created_at: Time.current, updated_at: Time.current }
        described_class.insert_all!([values])
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(described_class.where(account: account)).to be_empty
  end

  it 'does not admit duplicate status rows or NULL active via direct SQL' do
    state = described_class.create!(account: account, team: team, active: false)
    expect do
      described_class.transaction(requires_new: true) do
        described_class.insert_all!([state.attributes.except('id')])
      end
    end.to raise_error(ActiveRecord::RecordNotUnique)
    expect do
      described_class.transaction(requires_new: true) { state.update_columns(active: nil) }
    end.to raise_error(ActiveRecord::NotNullViolation)
    expect(state.reload).not_to be_active
  end

  it 'uses native optimistic locking instead of accepting a stale status update' do
    state = described_class.create!(account: account, team: team, active: false)
    stale = described_class.find(state.id)
    state.update!(active: true)
    expect { stale.update!(active: true) }.to raise_error(ActiveRecord::StaleObjectError)
    expect(state.reload.lock_version).to eq(1)
  end

  it 'removes only this extension when its native team is deleted' do
    state = described_class.create!(account: account, team: team, active: false)
    Team.where(account: account, id: team.id).delete_all
    expect(described_class.exists?(state.id)).to be(false)
    expect(Account.exists?(account.id)).to be(true)
  end

  it 'removes owned status rows on native account cascade without touching another account' do
    state = described_class.create!(account: account, team: team, active: false)
    foreign = create(:team, account: create(:account))
    other = described_class.create!(account: foreign.account, team: foreign, active: false)
    Account.where(id: account.id).delete_all
    expect(described_class.exists?(state.id)).to be(false)
    expect(other.reload).not_to be_active
  end
end

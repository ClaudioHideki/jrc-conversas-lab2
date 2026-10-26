require 'rails_helper'

describe OnlineStatusTracker do
  let!(:account) { create(:account) }
  let!(:user1) { create(:user, account: account) }
  let!(:user2) { create(:user, account: account) }
  let!(:user3) { create(:user, account: account) }

  context 'when get_available_users' do
    before do
      described_class.update_presence(account.id, 'User', user1.id)
      described_class.update_presence(account.id, 'User', user2.id)
    end

    it 'returns only the online user ids with presence' do
      expect(described_class.get_available_users(account.id).keys).to contain_exactly(user1.id.to_s, user2.id.to_s)
      expect(described_class.get_available_users(account.id).values).not_to include(user3.id)
    end

    it 'returns agents who have auto offline configured false' do
      user2.account_users.first.update(auto_offline: false)
      expect(described_class.get_available_users(account.id).keys).to contain_exactly(user1.id.to_s, user2.id.to_s)
    end

    it 'returns the availability from the db if it is not present in redis and set it in redis' do
      user2.account_users.find_by(account_id: account.id).update!(availability: 'offline')
      # clear the redis cache to ensure values are fetched from db
      Redis::Alfred.delete(format(Redis::Alfred::ONLINE_STATUS, account_id: account.id))
      expect(described_class.get_available_users(account.id)[user1.id.to_s]).to eq('online')
      expect(described_class.get_available_users(account.id)[user2.id.to_s]).to eq('offline')
      # ensure online status is also set
      expect(Redis::Alfred.hmget(format(Redis::Alfred::ONLINE_STATUS, account_id: account.id),
                                 [user1.id.to_s, user2.id.to_s])).to eq(%w[online offline])
    end
  end

  context 'when get_available_contacts' do
    let(:online_contact) { create(:contact, account: account) }
    let(:offline_contact) { create(:contact, account: account) }

    before do
      described_class.update_presence(account.id, 'Contact', online_contact.id)
      # creating a stale record for offline contact presence
      Redis::Alfred.zadd(format(Redis::Alfred::ONLINE_PRESENCE_CONTACTS, account_id: account.id),
                         (Time.zone.now - (OnlineStatusTracker::CONTACT_PRESENCE_DURATION + 20)).to_i, offline_contact.id)
    end

    it 'returns only the online contact ids with presence' do
      expect(described_class.get_available_contacts(account.id).keys).to contain_exactly(online_contact.id.to_s)
    end

    it 'flushes the stale records from sorted set after the duration' do
      described_class.get_available_contacts(account.id)
      expect(Redis::Alfred.zscore(format(Redis::Alfred::ONLINE_PRESENCE_CONTACTS, account_id: account.id), offline_contact.id)).to be_nil
    end
  end

  describe '.live_presence' do
    it 'shows a connected paused or offline session without making it automatically assignable' do
      user1.account_users.find_by!(account: account).update!(availability: :busy)
      user2.account_users.find_by!(account: account).update!(availability: :offline)
      user3.account_users.find_by!(account: account).update!(auto_offline: false)
      described_class.update_presence(account.id, 'User', user1.id)
      described_class.update_presence(account.id, 'User', user2.id)

      expect(described_class.live_presence(account.id)[:user_ids]).to contain_exactly(user1.id, user2.id)
      expect(described_class.effective_available_users(account.id)).to be_empty
    end

    it 'requires membership in the same account even if a heartbeat exists in its Redis key' do
      foreign_user = create(:user, account: create(:account))
      described_class.update_presence(account.id, 'User', foreign_user.id)
      described_class.update_presence(account.id, 'User', user1.id)

      expect(described_class.live_presence(account.id)[:user_ids]).to eq([user1.id])
      travel described_class::PRESENCE_DURATION + 1.second do
        expect(described_class.live_presence(account.id)[:user_ids]).to be_empty
      end
    end

    it 'fails closed on Redis failure independently of configured availability' do
      allow(Redis::Alfred).to receive(:zrangebyscore).and_raise(Redis::CannotConnectError)

      expect(described_class.live_presence(account.id)).to eq(user_ids: [], reason: 'redis_presence_unavailable')
    end
  end

  describe '.effective_presence' do
    it 'requires recent presence and the account configured online status' do
      described_class.update_presence(account.id, 'User', user1.id)
      described_class.update_presence(account.id, 'User', user2.id)
      user2.account_users.find_by!(account: account).update!(availability: :offline)
      user3.account_users.find_by!(account: account).update!(auto_offline: false)

      expect(described_class.effective_available_users(account.id)).to eq(user1.id.to_s => 'online')
      expect(user3.account_users.find_by!(account: account).availability_status).to eq('online')
    end

    it 'expires a disconnected session and admits a fresh reconnect heartbeat' do
      travel_to Time.current.change(usec: 0) do
        described_class.update_presence(account.id, 'User', user1.id)
        travel OnlineStatusTracker::PRESENCE_DURATION + 1.second
        expect(described_class.effective_available_users(account.id)).to be_empty
        described_class.update_presence(account.id, 'User', user1.id)
        expect(described_class.effective_available_users(account.id)).to eq(user1.id.to_s => 'online')
      end
    end

    it 'ignores the cached status and checks the correct account membership' do
      foreign = create(:account)
      create(:account_user, account: foreign, user: user1, availability: :offline)
      described_class.update_presence(account.id, 'User', user1.id)
      described_class.update_presence(foreign.id, 'User', user1.id)
      described_class.set_status(foreign.id, user1.id, 'online')

      expect(described_class.effective_available_users(account.id)).to eq(user1.id.to_s => 'online')
      expect(described_class.effective_available_users(foreign.id)).to be_empty
    end

    it 'fails closed when Redis cannot read presence' do
      allow(Redis::Alfred).to receive(:zrangebyscore).and_raise(Redis::CannotConnectError)

      expect(described_class.effective_presence(account.id)).to eq(user_ids: [], reason: 'redis_presence_unavailable')
      expect(described_class.effective_available_users(account.id)).to be_empty
    end
  end
end

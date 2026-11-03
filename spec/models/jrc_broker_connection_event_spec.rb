require 'rails_helper'

RSpec.describe JrcBrokerConnectionEvent do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:event) { described_class.create!(account: account, inbox: inbox, event_type: 'CONNECTED', occurred_at: Time.current) }

  it 'rejects secrets and cross-tenant references at creation' do
    unsafe = described_class.new(account: account, inbox: inbox, event_type: 'CONNECTED', occurred_at: Time.current, metadata: { qr: 'secret' })
    expect(unsafe).not_to be_valid
    unsafe.metadata = {}
    unsafe.inbox = create(:channel_api).inbox
    expect(unsafe).not_to be_valid
  end

  it 'prevents model and SQL alteration or deletion of persisted events' do
    expect { event.update!(event_type: 'DISCONNECTED') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { event.delete }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect do
      described_class.transaction(requires_new: true) { described_class.where(id: event.id).update_all(event_type: 'DISCONNECTED') }
    end.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
    expect do
      described_class.transaction(requires_new: true) { described_class.where(id: event.id).delete_all }
    end.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
  end
end

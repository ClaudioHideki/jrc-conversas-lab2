require 'rails_helper'

RSpec.describe Message do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  it 'does not regress database or websocket activity when an older message uses a stale conversation object' do
    stale = Conversation.find(conversation.id)
    recent = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)
    older = create(:message, account: account, inbox: inbox, conversation: stale, message_type: :incoming, created_at: 1.day.ago)
    expect(conversation.reload.last_activity_at.to_i).to eq(recent.created_at.to_i)
    expect(older.conversation.last_activity_at.to_i).to eq(conversation.last_activity_at.to_i)
    expect(older.push_event_data.dig(:conversation, :last_activity_at)).to eq(conversation.last_activity_at.to_i)
  end

  it 'applies a trusted internal builder block before saving and dispatching normal callbacks' do
    clock = 1.day.ago.change(usec: 0)
    clear_enqueued_jobs
    builder = Messages::MessageBuilder.new(nil, conversation, content: 'Synthetic internal clock', message_type: 'incoming')
    message = builder.perform { |row| row.created_at = clock }
    expect(message.reload.created_at).to eq(clock)
    expect(message.push_event_data[:created_at]).to eq(clock.to_i)
    expect(enqueued_jobs.map { |job| job[:job] }).to include(ActionCableBroadcastJob)
  end

  it 'preserves pending caller attributes while dispatching the persisted conversation clock' do
    conversation.custom_attributes = { 'synthetic_pending' => 'retained' }

    message = conversation.messages.create!(account: account, inbox: inbox, message_type: :incoming, content: 'Synthetic clock isolation')
    persisted = Conversation.find(conversation.id)

    expect(conversation.custom_attributes).to eq('synthetic_pending' => 'retained')
    expect(conversation.will_save_change_to_custom_attributes?).to be(true)
    expect(persisted.custom_attributes).to eq({})
    expect(message.conversation.custom_attributes).to eq('synthetic_pending' => 'retained')
    expect(message.push_event_data.dig(:conversation, :last_activity_at)).to eq(persisted.last_activity_at.to_i)
  end

  it 'continues ignoring generic caller timestamp parameters' do
    clock = 1.day.ago
    message = Messages::MessageBuilder.new(nil, conversation, content: 'Synthetic generic clock', message_type: 'incoming',
                                                              created_at: clock, occurred_at: clock.to_i).perform
    expect(message.created_at).to be_within(5.seconds).of(Time.current)
  end

  it 'ignores a foreign Account publication row in the unread cursor and aggregate' do
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: 1.day.ago)
    other_inbox = create(:channel_api).inbox
    JrcBrokerLiveReceipt.create!(account: other_inbox.account, inbox: other_inbox, message: message, state: 'PERSISTED',
                                 access_token_sha256: 'a' * 64, request_hash: 'b' * 64, envelope: {}, organization_id: SecureRandom.uuid,
                                 integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid, broker_message_id: SecureRandom.uuid,
                                 destination_revision: 1, conversation_id: 1, published_at: Time.current)
    expect(described_class.where(id: message.id).received_since(1.minute.ago)).to be_empty
    row = account.conversations.where(id: conversation.id)
                 .select(Conversation.arel_table[Arel.star], Conversation.unread_messages_count_arel.as('publication_unread')).first
    expect(row['publication_unread'].to_i).to eq(0)
  end
end

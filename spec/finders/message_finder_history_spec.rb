require 'rails_helper'

RSpec.describe MessageFinder, 'historical pagination' do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :resolved) }
  let(:stamp) { Time.utc(2026, 11, 4, 10) }
  let(:base_attributes) do
    { account_id: account.id, inbox_id: inbox.id, conversation_id: conversation.id,
      content_type: Message.content_types.fetch('text'), message_type: Message.message_types.fetch('incoming'),
      status: Message.statuses.fetch('delivered'), private: false, additional_attributes: {} }
  end
  let!(:live_messages) do
    Message.insert_all!(21.times.map do |index|
      base_attributes.merge(content: "Live #{index}", created_at: stamp + index.minutes, updated_at: stamp + index.minutes,
                            content_attributes: {})
    end)
    conversation.messages.reorder(:created_at, :id).to_a
  end
  let!(:historical_messages) do
    inserted = Message.insert_all!(9.times.map do |index|
      base_attributes.merge(content: "History #{index}", source_id: "jrc-history:#{SecureRandom.uuid}",
                            created_at: stamp - 1.day + index.minutes, updated_at: stamp - 1.day + index.minutes,
                            content_attributes: { jrc_broker_historical: true })
    end, returning: %w[id])
    conversation.messages.where(id: inserted.rows.flatten).reorder(:created_at, :id).to_a
  end

  it 'loads the newest twenty messages by occurrence rather than later historical insertion' do
    expect(described_class.new(conversation, {}).perform.map(&:id)).to eq(live_messages.last(20).map(&:id))
  end

  it 'reaches older imported messages when paging before the latest live page' do
    latest = described_class.new(conversation, {}).perform
    older = described_class.new(conversation, before: latest.first.id).perform

    expect(older.map(&:id)).to eq((historical_messages + live_messages.first(1)).map(&:id))
    expect((older + latest).map(&:id)).to eq((historical_messages + live_messages).map(&:id))
  end

  it 'retains numeric ingestion cursors when fetching messages created after a live message' do
    result = described_class.new(conversation, after: live_messages.first.id).perform

    expect(result.map(&:id)).to eq((historical_messages + live_messages.drop(1)).map(&:id))
  end

  it 'keeps inclusive after and exclusive before as numeric ingestion bounds' do
    result = described_class.new(conversation, after: live_messages.first.id, before: historical_messages.last.id).perform

    expect(result.map(&:id)).to eq((historical_messages.first(8) + live_messages).map(&:id))
  end

  it 'allows synthetic after cursors that do not identify an existing message' do
    expect(described_class.new(conversation, after: 0).perform.map(&:id)).to eq((historical_messages + live_messages).map(&:id))
  end

  it 'allows synthetic numeric bounds used to retrieve a range around a message' do
    result = described_class.new(conversation, after: 0, before: historical_messages.last.id + 100).perform

    expect(result.map(&:id)).to eq((historical_messages + live_messages).map(&:id))
  end

  it 'uses the unfiltered conversation to resolve an internal message anchor' do
    inserted = Message.insert_all!([base_attributes.merge(content: 'Internal anchor', private: true,
                                                         created_at: stamp - 1.hour, updated_at: stamp - 1.hour,
                                                         content_attributes: {})], returning: %w[id])
    result = described_class.new(conversation, before: inserted.rows.first.first, filter_internal_messages: true).perform

    expect(result.map(&:id)).to eq(historical_messages.map(&:id))
  end

  context 'when timestamps are identical' do
    before { conversation.messages.update_all(created_at: stamp, updated_at: stamp) }

    it 'uses ascending message ids to break ties in the latest page' do
      expected = (live_messages + historical_messages).last(20).map(&:id)

      expect(described_class.new(conversation, {}).perform.map(&:id)).to eq(expected)
    end

    it 'keeps adjacent before and after pages disjoint at a tied timestamp' do
      ordered = live_messages + historical_messages
      anchor = ordered.fetch(15)
      older = described_class.new(conversation, before: anchor.id).perform
      newer = described_class.new(conversation, after: anchor.id).perform

      expect(older.map(&:id)).to eq(ordered.first(15).map(&:id))
      expect(newer.map(&:id)).to eq(ordered.drop(16).map(&:id))
    end
  end

  it 'does not use a before anchor from another conversation in the same account' do
    other_conversation = create(:conversation, account: account, inbox: inbox)
    anchor = create(:message, account: account, inbox: inbox, conversation: other_conversation)

    expect(described_class.new(conversation, before: anchor.id).perform).to be_empty
  end

  it 'does not use a before anchor belonging to another tenant' do
    foreign = create(:message)

    expect(described_class.new(conversation, before: foreign.id).perform).to be_empty
  end

  it 'returns no messages when a supplied before anchor no longer exists' do
    expect(described_class.new(conversation, before: 0).perform).to be_empty
    expect(described_class.new(conversation, before: historical_messages.last.id + 100).perform).to be_empty
  end

  it 'does not mutate history or attendance or enqueue delivery while reading successive pages' do
    before_state = conversation.reload.attributes
    message_state = conversation.messages.reorder(:id).map(&:attributes)
    clear_enqueued_jobs

    described_class.new(conversation, {}).perform.to_a
    described_class.new(conversation, before: live_messages.first.id).perform.to_a
    described_class.new(conversation, after: historical_messages.first.id).perform.to_a

    expect(conversation.reload.attributes).to eq(before_state)
    expect(conversation.messages.reorder(:id).map(&:attributes)).to eq(message_state)
    expect(enqueued_jobs).to be_empty
  end
end

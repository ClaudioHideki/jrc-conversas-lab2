require 'rails_helper'

RSpec.describe JrcRelationship::SentimentSignals do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact, inbox: inbox, assignee: actor) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: contact) }
  let(:context) { JrcRelationship::Context.new(member) }
  let(:customer) { assignment.customer_context(member) }
  let(:message) do
    create(:message, account: account, conversation: conversation, inbox: inbox, sender: contact, message_type: :incoming,
                     sentiment: { 'label' => 'negative' }, created_at: 40.days.ago)
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'preserves the native90-day default with the actual recognized public message timestamp and no inference' do
    original = message.reload.attributes.deep_dup
    result = described_class.new(context: context, customer: customer,
                                 window_days: JrcRelationship::Configuration::DEFAULT_RULES.fetch('sentiment_window_days')).call
    expect(result).to include(normalized: 20.0, source_ids: [message.id])
    expect(result[:measurement]).to include(state: 'current', window_days: 90, observed_at: message.created_at.iso8601(6), sample_limit: 100)
    expect(message.reload.attributes).to eq(original)
  end

  it 'marks older authorized sentiment stale without giving it a score in the new window' do
    message
    result = described_class.new(context: context, customer: customer, window_days: 14).call
    expect(result).to include(normalized: nil, raw: [], source_ids: [message.id])
    expect(result[:measurement]).to include(state: 'stale', observed_at: message.created_at.iso8601(6), window_days: 14)
  end

  it 'ignores private, future, activity and foreign-customer messages even when they carry recognized sentiment' do
    create(:message, account: account, conversation: conversation, inbox: inbox, private: true, sentiment: { 'label' => 'critical' })
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :activity, sentiment: { 'label' => 'critical' })
    create(:message, account: account, conversation: conversation, inbox: inbox, sentiment: { 'label' => 'critical' }, created_at: 1.day.from_now)
    other = create(:conversation, account: account, contact: create(:contact, account: account), inbox: inbox)
    create(:message, account: account, conversation: other, inbox: inbox, sentiment: { 'label' => 'positive' })
    create(:message, sentiment: { 'label' => 'positive' })
    result = described_class.new(context: context, customer: customer, window_days: 14).call
    expect(result).to include(normalized: nil, raw: [], source_ids: [])
    expect(result[:measurement]).to include(state: 'missing', observed_at: nil)
  end

  it 'never uses an unrecognized newer analysis timestamp as the actual observation date' do
    message
    create(:message, account: account, conversation: conversation, inbox: inbox, sentiment: { 'label' => 'unsupported' })
    result = described_class.new(context: context, customer: customer, window_days: 90).call
    expect(result[:measurement][:observed_at]).to eq(message.created_at.iso8601(6))
    expect(result[:source_ids]).to eq([message.id])
  end

  it 'reuses a stable observation during refresh without manufacturing new source timestamps or fingerprints' do
    message
    source = described_class.new(context: context, customer: customer, window_days: 90)
    first = source.call
    second = described_class.new(context: context, customer: customer, window_days: 90, now: 1.hour.from_now).call
    expect(second).to eq(first)
    health = JrcRelationship::CustomerSignals.new(assignment: assignment, context: context).call
    factor = health[:health][:factors].find { |row| row[:factor] == 'sentiment' }
    expect(factor[:measurement]).to include(state: 'current', observed_at: message.created_at.iso8601(6))
    expect(health[:_source_ids][:messages]).to include(message.id)
  end

  it 'keeps the native one-hundred-message bound and bases the observation on the selected actual source' do
    oldest = message
    100.times do |index|
      create(:message, account: account, conversation: conversation, inbox: inbox, sender: contact, message_type: :incoming,
                       sentiment: { 'label' => 'neutral' }, created_at: 1.day.ago + index.seconds)
    end
    result = described_class.new(context: context, customer: customer, window_days: 90).call
    expect(result).to include(normalized: 60.0)
    expect([result[:raw].size, result[:source_ids].size]).to eq([100, 100])
    expect(result[:source_ids]).not_to include(oldest.id)
  end

  it 'requires the native inbox grant even for a CS-owned customer in the same account' do
    message
    member.update!(role: :agent)
    denied = described_class.new(context: context, customer: customer, window_days: 90).call
    expect(denied).to include(normalized: nil, source_ids: [])
    expect(denied[:measurement]).to include(state: 'missing', observed_at: nil)
    create(:inbox_member, user: actor, inbox: inbox)
    allowed = described_class.new(context: JrcRelationship::Context.new(member.reload),
                                  customer: assignment.customer_context(member), window_days: 90).call
    expect(allowed).to include(normalized: 20.0, source_ids: [message.id])
  end
end

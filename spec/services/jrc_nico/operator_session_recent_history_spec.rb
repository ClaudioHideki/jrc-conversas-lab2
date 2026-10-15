require 'rails_helper'

RSpec.describe JrcNico::OperatorSession do
  let(:account) { create(:account, custom_attributes: { 'nico_enabled' => true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account) }
  let(:operator) { described_class.new(account: account, user: admin) }

  before do
    45.times do |index|
      create(:message, account: account, conversation: conversation, sender: conversation.contact,
                       content: "Public message #{index + 1}", private: false, created_at: 2.days.ago + index.minutes)
    end
    create(:message, account: account, conversation: conversation, content: 'Private account note', private: true)
    create(:message, account: account, content: 'Other conversation secret')
    create(:message, content: 'Other account secret')
  end

  it 'gives the operator the latest thirty public messages in chronological order' do
    context = nil
    allow(JrcNico::OperationalInference).to receive(:call) do |**options|
      context = options.fetch(:context)
      { 'reply' => 'History reviewed', 'tool' => '', 'arguments' => {} }
    end

    command = operator.ask(message: 'Resuma a conversa selecionada', request_id: SecureRandom.uuid,
                           conversation_id: conversation.display_id)

    expect(command.status).to eq('succeeded')
    expect(context.fetch(:conversation).pluck(:content)).to eq((16..45).map { |index| "Public message #{index}" })
  end

  it 'samples the latest five public messages for opportunity analysis' do
    rows = JrcNico::ToolExecutor.new(operator.access).conversation_sample_messages(conversation)

    expect(rows.pluck(:content)).to eq(['Public message 41', 'Public message 42', 'Public message 43', 'Public message 44', 'Public message 45'])
  end

  it 'reads the latest thirty public messages through the authorized conversation tool' do
    result = JrcNico::ToolExecutor.new(operator.access).call('read_conversation', 'conversation_id' => conversation.display_id)

    expect(result.fetch(:messages).pluck('content')).to eq((16..45).map { |index| "Public message #{index}" })
  end

  it 'gives a delegated customer turn the latest forty public messages without internal notes' do
    delegation = JrcNico::Delegation.new(
      account: account, user: admin, conversation: conversation,
      objective: 'Atendimento de teste', allowed_actions: []
    )
    access = JrcNico::Access.new(account: account, user: admin, conversation: conversation).authorize!
    context = JrcNico::CustomerTurnJob.new.send(:customer_context, delegation, access)

    expect(context.fetch(:conversation).pluck(:content)).to eq((6..45).map { |index| "Public message #{index}" })
  end

  it 'does not read another Account through the conversation tool' do
    foreign = create(:conversation)
    foreign.update!(display_id: 1_000_000)
    expect do
      JrcNico::ToolExecutor.new(operator.access).call('read_conversation', 'conversation_id' => foreign.display_id)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'builds analysis context from the latest forty public messages' do
    context = JrcNico::ContextBuilder.new(account: account, user: admin, conversation: conversation).build('resumo')

    expect(context.fetch(:conversation).pluck(:text)).to eq((6..45).map { |index| "incoming: Public message #{index}" })
  end

  it 'claims the latest pending incoming message so an older superseded turn does not block the delegation' do
    bot = create(:agent_bot, account: account)
    conversation.update!(status: :pending, assignee_agent_bot_id: bot.id)
    delegation = JrcNico::Delegation.create!(
      account: account, user: admin, conversation: conversation, agent_bot: bot,
      objective: 'Atendimento de teste', allowed_actions: [], expires_at: 1.hour.from_now
    )
    latest = create(:message, account: account, conversation: conversation, sender: conversation.contact, content: 'Latest pending request')

    turn = JrcNico::CustomerTurnJob.new.send(:claim, delegation, conversation)

    expect(turn.message_id).to eq(latest.id)
  end
end

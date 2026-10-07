require 'rails_helper'

RSpec.describe JrcAi::ConversationSentiment do
  let(:account) { create(:account, custom_attributes: { 'nico_enabled' => true }) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:access) { JrcNico::OperationalAccess.new(account: account, user: user).authorize! }
  let(:conversation) { create(:conversation, account: account) }
  let(:report) { { 'summary' => 'Amostra analisada', 'evidence' => [] } }
  let(:runtime) { instance_double(JrcNico::RuntimeClient) }

  before do
    allow(JrcNico::OperationalInference).to receive(:metered).and_yield(nil)
    allow(JrcNico::RuntimeClient).to receive(:new).with(provider: nil).and_return(runtime)
    allow(runtime).to receive(:sentiment).and_return('report' => report, 'model' => 'test-model')
  end

  it 'includes only public texts, distinguishes human, bot and unknown authors, and identifies the source window' do
    customer = create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'Olá', private: false)
    human = create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: user, content: 'Como posso ajudar?',
                             private: false)
    bot = create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: nil,
                           content: 'Escolha uma opção', private: false, content_attributes: { jrc_flow_run_id: 123 })
    unknown = create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: nil,
                               content: 'Autoria não identificada', private: false)
    unknown.update!(sender: nil)
    create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: user, content: 'NOTA_INTERNA', private: true)
    result = described_class.call(access, conversation.display_id)
    expect(runtime).to have_received(:sentiment).with(hash_including(
                                                        account_id: account.id, conversation_id: conversation.display_id,
                                                        messages: [
                                                          { id: customer.id, role: 'customer', content: 'Olá' },
                                                          { id: human.id, role: 'operator', content: 'Como posso ajudar?' },
                                                          { id: bot.id, role: 'bot', content: 'Escolha uma opção' },
                                                          { id: unknown.id, role: 'unknown', content: 'Autoria não identificada' }
                                                        ]
                                                      ))
    expect(result[:sentiment_report]).to include('message_count' => 4, 'conversation_id' => conversation.display_id)
    expect(result.to_json).not_to include('NOTA_INTERNA')
  end

  it 'rejects a conversation from another account before invoking AI' do
    foreign = create(:conversation, display_id: 100_000)
    expect { described_class.call(access, foreign.display_id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(runtime).not_to have_received(:sentiment)
  end

  it 'selects the latest 100 public messages in chronological order despite the message default scope' do
    rows = Array.new(105) do |index|
      create(:message, account: account, conversation: conversation, message_type: :incoming,
                       content: "Mensagem #{index}", private: false, created_at: (200 - index).minutes.ago)
    end
    described_class.call(access, conversation.display_id)
    expect(runtime).to have_received(:sentiment) do |payload|
      expect(payload[:messages].size).to eq(100)
      expect(payload[:messages].map { |row| row[:id] }).to eq(rows.last(100).map(&:id))
    end
  end

  it 'rechecks the operator policy before reading messages' do
    allow(access).to receive(:conversation).with(conversation.display_id).and_raise(Pundit::NotAuthorizedError)
    expect { described_class.call(access, conversation.display_id) }.to raise_error(Pundit::NotAuthorizedError)
    expect(runtime).not_to have_received(:sentiment)
  end
end

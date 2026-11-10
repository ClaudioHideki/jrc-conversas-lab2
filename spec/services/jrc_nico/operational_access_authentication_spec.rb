require 'rails_helper'

RSpec.describe JrcNico::OperationalAccess do
  let(:account) { create(:account, custom_attributes: { 'nico_enabled' => true }) }
  let(:actor) { create(:user, account: account, role: :administrator, confirmed_at: Time.current) }
  let(:access) { described_class.new(account: account, user: actor) }
  let(:conversation) { create(:conversation, account: account) }
  let(:conversation_access) { JrcNico::Access.new(account: account, user: User.find(actor.id), conversation: conversation) }
  let(:operator) { JrcNico::OperatorSession.new(account: account, user: actor) }

  it 'rechecks a persisted native authentication revocation even when both access objects still hold a confirmed User instance' do
    access.authorize!
    conversation_access.authorize!
    User.find(actor.id).update!(confirmed_at: nil)
    expect(actor.confirmed_at).to be_present
    expect(conversation_access.user.confirmed_at).to be_present
    expect { access.authorize! }.to raise_error(Pundit::NotAuthorizedError)
    expect { conversation_access.authorize! }.to raise_error(Pundit::NotAuthorizedError)
    expect(account.account_users.exists?(user_id: actor.id)).to be(true)
  end

  it 'does not confuse offline presence with loss of native authentication eligibility' do
    account.account_users.find_by!(user: actor).update!(availability: :offline)
    expect(access.authorize!).to eq(access)
    expect(conversation_access.authorize!).to eq(conversation_access)
  end

  it 'rejects an already prepared native write after authentication is revoked without creating a contact or leaving a success receipt' do
    command = operator.ask(message: 'Synthetic reviewed contact', request_id: SecureRandom.uuid,
                           prepared: { 'tool' => 'create_contact', 'arguments' => {
                             'name' => 'Synthetic blocked native contact', 'email' => 'blocked-native@example.test'
                           } })
    before = account.contacts.count
    User.find(actor.id).update!(confirmed_at: nil)
    expect { operator.execute(command) }.to raise_error(Pundit::NotAuthorizedError)
    expect(account.contacts.count).to eq(before)
    expect(command.reload.status).to eq('failed')
  end

  it 'retains a valid confirmed actor native write and its existing idempotence' do
    command = operator.ask(message: 'Synthetic authorized contact', request_id: SecureRandom.uuid,
                           prepared: { 'tool' => 'create_contact', 'arguments' => {
                             'name' => 'Synthetic authorized native contact', 'email' => 'authorized-native@example.test'
                           } })
    expect { operator.execute(command) }.to change(account.contacts, :count).by(1)
    expect { operator.execute(command) }.not_to change(account.contacts, :count)
    expect(command.reload.status).to eq('succeeded')
  end

  it 'fails a queued native plan before any model inference when the persisted actor is no longer authenticated' do
    command = operator.ask(message: 'Synthetic queued read', request_id: SecureRandom.uuid, async: true)
    User.find(actor.id).update!(confirmed_at: nil)
    allow(JrcNico::OperationalInference).to receive(:call).and_return({ 'reply' => 'Synthetic inference must not be dispatched' })
    JrcNico::PlanCommandJob.perform_now(command.id)
    expect(command.reload.status).to eq('failed')
    expect(JrcNico::OperationalInference).not_to have_received(:call)
  end

  it 'does not accept a late inference answer after native authentication changes during planning' do
    session = operator.session
    allow(JrcNico::OperationalInference).to receive(:call) do
      User.find(actor.id).update!(confirmed_at: nil)
      { 'reply' => 'Synthetic private late inference answer' }
    end
    request_id = SecureRandom.uuid
    expect { operator.ask(message: 'Synthetic read while eligibility changes', request_id: request_id) }.to raise_error(Pundit::NotAuthorizedError)
    expect(session.commands.find_by!(request_id: request_id).status).to eq('failed')
    expect(session.reload.messages.to_json).not_to include('Synthetic private late inference answer')
  end

  it 'returns a delegated customer turn to native human attention before inference when its actor becomes unconfirmed' do
    with_modified_env(FRONTEND_URL: 'https://nico-auth.example.test') do
      bot = create(:agent_bot, account: account)
      conversation.update!(status: :pending, assignee_agent_bot_id: bot.id)
      delegation = JrcNico::Delegation.create!(account: account, user: actor, conversation: conversation, agent_bot: bot,
                                               objective: 'Synthetic authorized assistance', allowed_actions: [], expires_at: 1.hour.from_now)
      create(:message, account: account, conversation: conversation, sender: conversation.contact, content: 'Synthetic customer question')
      User.find(actor.id).update!(confirmed_at: nil)
      allow(JrcNico::OperationalInference).to receive(:call).and_return({ 'reply' => 'No provider dispatch is allowed' })
      JrcNico::CustomerTurnJob.perform_now(delegation.id)
      expect(delegation.reload.status).to eq('needs_human')
      expect(delegation.turns.last!.status).to eq('failed')
      expect(conversation.messages.outgoing).to be_empty
      expect(JrcNico::OperationalInference).not_to have_received(:call)
    end
  end
end

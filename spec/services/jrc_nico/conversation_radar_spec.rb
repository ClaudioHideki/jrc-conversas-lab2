require 'rails_helper'

RSpec.describe JrcNico::ConversationRadar do
  let(:account) { create(:account, custom_attributes: { 'nico_enabled' => true }) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:access) { JrcNico::OperationalAccess.new(account: account, user: user) }
  let(:executor) { JrcNico::ToolExecutor.new(access) }

  around { |example| travel_to(Time.zone.parse('2026-10-16 12:00:00')) { example.run } }

  def radar(arguments = {})
    executor.call('read_conversation_radar', arguments)
  end

  def conversation(**attributes)
    value = create(:conversation, account: account, inbox: inbox, status: :open)
    # Historical native state must not trigger a fresh inbound-message callback.
    value.update_columns({ assignee_id: nil, assignee_agent_bot_id: nil, waiting_since: nil, # rubocop:disable Rails/SkipsModelValidations
                           last_activity_at: Time.current, created_at: 2.days.ago }.merge(attributes))
    value
  end

  it 'reports deterministic native criteria without treating waiting or inactivity as contractual SLA' do
    waiting = conversation(waiting_since: 11.minutes.ago)
    recent = conversation(waiting_since: 2.minutes.ago, assignee_id: user.id)
    bot = create(:agent_bot, account: account)
    bot_owned = conversation(assignee_agent_bot_id: bot.id)
    inactive = conversation(last_activity_at: 25.hours.ago)
    conversation(status: Conversation.statuses.fetch('resolved'), waiting_since: 2.hours.ago)
    conversation(waiting_since: 1.hour.from_now, assignee_id: user.id)

    result = radar
    expect(result).to include(version: 1, generated_at: Time.current.iso8601, window: 'active_backlog', waiting_threshold_is_sla: false)
    expect(result.fetch(:categories).fetch('waiting')[:total]).to eq(2)
    expect(result.fetch(:categories).fetch('waiting_alert')[:items].pluck(:conversation_id)).to eq([waiting.display_id])
    expect(result.fetch(:categories).fetch('unassigned')[:items].pluck(:conversation_id)).not_to include(bot_owned.display_id, recent.display_id)
    expect(result.fetch(:categories).fetch('inactive')[:items].pluck(:conversation_id)).to eq([inactive.display_id])
    expect(result.to_json).not_to include('content', 'phone_number', 'email')
  end

  it 'counts the full authorized backlog while exposing only twenty rows per category and page' do
    seed = conversation
    rows = Array.new(205) { seed.attributes.slice(*Conversation.column_names).except('id', 'display_id', 'uuid') }
    Conversation.insert_all!(rows) # rubocop:disable Rails/SkipsModelValidations -- bulk fixture exceeds the assistant sample without 205 unrelated callbacks
    allow(access).to receive(:conversations).and_raise('Do not use the 200-row assistant sample')

    first = radar.fetch(:categories).fetch('unassigned')
    second = radar('page' => 2).fetch(:categories).fetch('unassigned')
    expect(first).to include(total: 206, has_more: true)
    expect(first[:items].length).to eq(20)
    expect(first[:items].pluck(:conversation_id) & second[:items].pluck(:conversation_id)).to be_empty
  end

  it 'excludes foreign Accounts and inboxes outside the current agent permissions' do
    visible = conversation
    create(:conversation)
    hidden = create(:channel_api, account: account).inbox
    create(:conversation, account: account, inbox: hidden)
    account.account_users.find_by!(user_id: user.id).update!(role: :agent)
    create(:inbox_member, inbox: inbox, user: user)

    expect(radar.fetch(:categories).fetch('unassigned')[:items].pluck(:conversation_id)).to eq([visible.display_id])
    expect { radar('inbox_id' => hidden.id) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rechecks revoked membership and rejects invalid pagination without side effects' do
    conversation
    expect { radar('page' => 0) }.to raise_error(ArgumentError)
    account.account_users.find_by!(user_id: user.id).destroy!
    expect { radar }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'does not expose the operator radar to a request originating from a customer conversation' do
    notice = instance_double(JrcNico::Notice, conversation: conversation)
    customer_executor = JrcNico::ToolExecutor.new(access, customer_notice: notice)

    expect { customer_executor.call('read_conversation_radar', {}) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'applies a restricted custom role even when the membership role is administrator' do
    own = conversation(assignee_id: user.id, waiting_since: 11.minutes.ago)
    denied = conversation(waiting_since: 11.minutes.ago)
    role = create(:custom_role, account: account, permissions: ['conversation_participating_manage'])
    account.account_users.find_by!(user_id: user.id).update!(custom_role: role)
    expect(access.policy(denied).show?).to be(false)

    group = radar.fetch(:categories).fetch('waiting')
    expect(group[:total]).to eq(1)
    expect(group[:items].pluck(:conversation_id)).to eq([own.display_id])
  end

  it 'preserves authorized conversation history without requiring the Relationship module' do
    conversation
    account.disable_features!('jrc_relationship')
    allow(JrcNico::OperationalInference).to receive(:call).and_return(
      { 'reply' => '', 'tool' => 'read_conversation_radar', 'arguments' => {} },
      { 'reply' => 'Radar consultado sem executar ações.', 'tool' => '', 'arguments' => {} }
    )
    operator = JrcNico::OperatorSession.new(account: account, user: user)
    command = operator.ask(message: 'Consulte meu radar', request_id: SecureRandom.uuid)
    expect(command.status).to eq('succeeded')
    saved = operator.session.reload.messages
    expect(saved).not_to be_empty

    reopened = JrcNico::OperatorSession.new(account: account, user: user)
    expect(reopened.session.messages).to eq(saved)
  end
end

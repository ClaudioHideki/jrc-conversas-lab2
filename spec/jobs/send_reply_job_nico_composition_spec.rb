require 'rails_helper'
require 'timeout'

RSpec.describe SendReplyJob do
  self.use_transactional_tests = false

  let(:account) { create(:account, custom_attributes: { 'nico_enabled' => true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account) }

  around do |example|
    disposable = %w[jrc_nico_gate_test jrc_nico_broker_candidate_test]
    database = ENV.fetch('POSTGRES_DATABASE', nil)
    enabled = Rails.env.test? && ENV['JRC_NICO_GATE_CONCURRENCY'] == '1' && disposable.include?(database) &&
              ActiveRecord::Base.connection_db_config.database == database &&
              ActiveRecord::Base.connection.adapter_name == 'PostgreSQL'
    skip 'Opt-in requires an explicitly named disposable NICO test database' unless enabled
    with_modified_env(FRONTEND_URL: 'https://host.example.test') do
      clear_committed_fixtures
      example.run
    ensure
      clear_committed_fixtures
      Current.reset
    end
  end

  def clear_committed_fixtures
    connection = ActiveRecord::Base.connection
    raise 'Committed fixtures cannot run inside an outer transaction' if connection.transaction_open?

    connection.clear_query_cache
    tables = connection.tables - %w[schema_migrations ar_internal_metadata installation_configs]
    previous_timeout = connection.select_value('SHOW lock_timeout')
    connection.execute("SET lock_timeout='2s'")
    begin
      connection.execute("TRUNCATE #{tables.map { |name| connection.quote_table_name(name) }.join(', ')} RESTART IDENTITY CASCADE")
    rescue ActiveRecord::LockWaitTimeout
      activity = connection.select_all('SELECT pid,state,wait_event_type FROM pg_stat_activity WHERE datname=current_database()')
      raise "Fixture cleanup was blocked; disposable DB sessions: #{activity.to_a.inspect}"
    ensure
      connection.execute("SET lock_timeout=#{connection.quote(previous_timeout)}")
    end
    connection.clear_query_cache
  end

  it 'does not send a queued bot reply after a public human message' do
    bot = AgentBot.create!(account: account, name: 'NICO QA')
    delegation = JrcNico::Delegation.create!(account: account, user: admin, conversation: conversation, agent_bot: bot,
                                             objective: 'Qualificar', expires_at: 1.hour.from_now)
    conversation.update!(status: 'pending', assignee_agent_bot: bot)
    message = Messages::MessageBuilder.new(
      bot, conversation,
      content: 'Pendente',
      content_attributes: { nico_delegation: { id: delegation.id, version: delegation.version } }
    ).perform
    Messages::MessageBuilder.new(admin, conversation, content: 'Assumi o atendimento').perform
    job = described_class.new
    expect(job).not_to receive(:deliver)
    job.perform(message.id)
    expect(message.reload.status).to eq('failed')
  end

  it 'does not retry a customer delivery with uncertain channel outcome' do
    bot = AgentBot.create!(account: account, name: 'NICO QA')
    delegation = JrcNico::Delegation.create!(account: account, user: admin, conversation: conversation, agent_bot: bot,
                                             objective: 'Qualificar', expires_at: 1.hour.from_now)
    conversation.update!(status: 'pending', assignee_agent_bot: bot)
    incoming = create(:message, conversation: conversation, account: account, message_type: :incoming, content: 'Olá')
    turn = delegation.turns.create!(message_id: incoming.id, version: delegation.version, status: 'queued')
    outgoing = Messages::MessageBuilder.new(
      bot, conversation,
      content: 'Olá!',
      content_attributes: { nico_turn_id: turn.id, nico_delegation: { id: delegation.id, version: delegation.version } }
    ).perform
    turn.update!(outgoing_message_id: outgoing.id)
    job = described_class.new
    expect(job).to receive(:deliver).once.and_raise(Timeout::Error)
    job.perform(outgoing.id)
    # A timeout cannot prove cancellation; a retry must retain the uncertain delivery fact.
    expect(turn.reload.status).to eq('unknown')
    expect { job.perform(outgoing.id) }.not_to(change { turn.reload.status })
    expect(delegation.reload).to have_attributes(status: 'needs_human', reason: 'delivery_unknown')
  end

  it 'hands definitive channel failures to the operator without retrying delivery' do
    bot = AgentBot.create!(account: account, name: 'NICO QA')
    delegation = JrcNico::Delegation.create!(account: account, user: admin, conversation: conversation, agent_bot: bot,
                                             objective: 'Qualificar', expires_at: 1.hour.from_now)
    conversation.update!(status: 'pending', assignee_agent_bot: bot)
    incoming = create(:message, conversation: conversation, account: account, message_type: :incoming, content: 'Olá')
    turn = delegation.turns.create!(message_id: incoming.id, version: delegation.version, status: 'queued')
    outgoing = Messages::MessageBuilder.new(
      bot, conversation,
      content: 'Olá!',
      content_attributes: { nico_turn_id: turn.id, nico_delegation: { id: delegation.id, version: delegation.version } }
    ).perform
    turn.update!(outgoing_message_id: outgoing.id)
    job = described_class.new
    expect(job).to(receive(:deliver).once { |message| message.update!(status: :failed) })
    job.perform(outgoing.id)
    expect(turn.reload.status).to eq('failed')
    expect(delegation.reload).to have_attributes(status: 'needs_human', reason: 'delivery_failed')
    expect(conversation.reload).to have_attributes(status: 'open', assignee_id: admin.id, assignee_agent_bot_id: nil)
    expect(JrcNico::Notice.where(account: account, user: admin, conversation: conversation, kind: 'attention').count).to eq(1)
    expect { job.perform(outgoing.id) }.not_to change(JrcNico::Notice, :count)
  end
end

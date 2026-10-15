class JrcFlows::RemoteRunner
  class Interrupted < StandardError; end

  def initialize(connection)
    @connection = connection
    @client = JrcFlows::ChatwootClient.new(connection)
  end

  def receive(payload)
    return unless remote_enabled?

    data = payload['conversation'] || payload
    id = data.fetch('id').to_i
    @session = @connection.remote_sessions.find_by(conversation_id: id)
    unless payload['event'] == 'message_created'
      stop!('Conversa transferida ou encerrada no Chatwoot.') if @session && %w[ready running waiting
                                                                                delayed].include?(@session.status) &&
                              data['status'].present? && data['status'] != 'pending'
      return
    end
    return unless ['incoming', 0].include?(payload['message_type']) && !payload['private']
    return if @session && (payload['id'].to_i <= @session.last_message_id || %w[paused failed completed running].include?(@session.status))

    remote = @client.conversation(id)
    return unless bot_owns?(remote)

    unless @session
      inbox_id = remote.fetch('inbox_id').to_i
      flow = @connection.flows.active.order(:id).detect do |candidate|
        Array(candidate.settings['inbox_ids']).include?(inbox_id) &&
          (candidate.settings['keyword'].blank? || payload['content'].to_s.downcase.include?(candidate.settings['keyword'].downcase))
      end
      return unless flow

      @session = @connection.remote_sessions.create!(flow: flow, conversation_id: id, inbox_id: inbox_id, flow_version: flow.lock_version,
                                                     node_id: flow.graph['nodes'].find do |n|
                                                       n['type'] == 'start'
                                                     end&.fetch('id'), variables: {
                                                       'contact.name' => remote.dig('meta', 'sender', 'name').to_s,
                                                       'contact.email' => remote.dig('meta', 'sender', 'email').to_s,
                                                       'contact.phone_number' => remote.dig('meta', 'sender', 'phone_number').to_s,
                                                       'conversation.id' => id.to_s
                                                     })
    end
    @flow = @session.flow
    @session.variables['message'] = payload['content'].to_s.first(10_000)
    previous_status = @session.status
    @session.update!(last_message_id: payload['id'], status: 'running', claimed_at: Time.current, wake_at: nil)
    if @flow.engine == 'workflow'
      workflow(remote)
    else
      if previous_status == 'waiting'
        node = current_node
        @session.variables[node['data']['variable']] = @session.variables['message']
        advance(node, 'next')
      elsif previous_status == 'delayed'
        return stop!('Cliente respondeu durante a espera.')
      end
      @session.save!
      native
    end
  rescue Interrupted
    stop!('Atendimento assumido, conexão desativada ou flow alterado.')
  rescue StandardError => e
    fail!(e)
    raise
  end

  def resume(session)
    return unless remote_enabled?

    @session = session
    @flow = session.flow
    node = current_node
    advance(node, session.status == 'waiting' ? 'timeout' : 'next')
    @session.update!(status: 'running', wake_at: nil, claimed_at: Time.current)
    native
  rescue Interrupted
    stop!('Atendimento assumido, conexão desativada ou flow alterado.')
  rescue StandardError => e
    fail!(e)
  end

  private

  def remote_enabled?
    JrcFlows::Access.external_beta? && @connection.reload.enabled? && JrcFlows::Access.enabled?(@connection.account.reload)
  end

  def bot_owns?(remote)
    assignee = remote.dig('meta', 'assignee')
    remote['status'] == 'pending' && (assignee.blank? || assignee['type'] == 'agent_bot') &&
      (remote.dig('meta', 'assignee_agent_bot', 'id').blank? || remote.dig('meta', 'assignee_agent_bot', 'id') == @connection.bot_id)
  end

  def guard!
    raise Interrupted unless @session.reload.status == 'running' && remote_enabled?
    raise Interrupted unless @flow.reload.status == 'active' && @flow.lock_version == @session.flow_version
    raise Interrupted unless @flow.account.account_users.exists?(user_id: @flow.created_by_id, role: 'administrator')
    raise Interrupted unless bot_owns?(@client.conversation(@session.conversation_id))

    @session.update!(claimed_at: Time.current)
  end

  def checkpoint(node)
    guard!
    @session.update!(node_id: node['id'],
                     trace: (@session.trace + [{ 'node_id' => node['id'], 'label' => node['name'] || node['label'], 'type' => node['type'],
                                                 'at' => Time.current.iso8601 }]).last(200))
    true
  end

  def workflow(remote)
    raise JrcFlows::WorkflowEngine::Error, 'Limite de 200 turnos atingido.' if @session.steps >= 200

    @session.update!(steps: @session.steps + 1)
    payload = { 'event_type' => 'MESSAGE', 'mensagem' => @session.variables['message'], 'human_active' => false,
                'conversation_id' => "remote-#{@connection.id}-#{@session.conversation_id}",
                'message_id' => "remote-#{@connection.id}-#{@session.last_message_id}",
                'tenant_id' => "jrc-#{@connection.account_id}-#{@connection.id}", 'telefone' => @session.variables['contact.phone_number'],
                'canal' => remote.dig('meta', 'channel').to_s, 'origem' => 'CHATWOOT', 'environment' => @flow.settings.fetch('environment', 'HML') }
    result = JrcFlows::WorkflowEngine.new(@flow, guard: ->(node) { checkpoint(node) }).perform(payload)
    response = JrcFlows::WorkflowResponse.normalize(result[:output])
    response['messages'].each { |message| send_message(message) } unless response['ignore']
    if response['handoff']
      key = { 'SUPORTE' => 'workflow_support_team_id', 'FINANCEIRO' => 'workflow_financial_team_id',
              'COMERCIAL' => 'workflow_commercial_team_id' }[response['destination'].to_s.upcase]
      team_id = @flow.settings[key].presence || @flow.settings['workflow_team_id']
      raise JrcFlows::WorkflowEngine::Error, 'Configure a equipe de transferência.' unless @flow.execution_team_ids.include?(team_id.to_i)

      send_message(response['summary'], private_note: true) if response['summary'].present?
      assign('team_id' => team_id)
    elsif response['close']
      status('resolved')
    else
      @session.update!(status: 'waiting')
    end
  end

  def native
    200.times do
      node = current_node
      return finish! unless node
      raise JrcFlows::WorkflowEngine::Error, 'Limite de 200 passos atingido.' if @session.steps >= 200

      checkpoint(node)
      @session.update!(steps: @session.steps + 1)
      data, type = node.values_at('data', 'type')
      evaluator = JrcFlows::Evaluator.new(@session.variables)
      port = 'next'
      case type
      when 'start' then nil
      when 'message', 'note' then send_message(evaluator.render(data['text']), private_note: type == 'note')
      when 'variable' then @session.variables[data['variable']] = evaluator.render(data['value'])
      when 'condition', 'switch' then port = evaluator.port(node)
      when 'input', 'delay'
        seconds = data[type == 'input' ? 'timeout' : 'seconds'].to_i.clamp(1, 604_800)
        @session.update!(status: type == 'input' ? 'waiting' : 'delayed', wake_at: seconds.seconds.from_now)
        JrcFlows::RemoteResumeJob.set(wait: seconds.seconds).perform_later(@session.id)
        return
      when 'labels'
        labels = JrcFlows::ChatwootClient.list(@client.call(:get, "conversations/#{@session.conversation_id}/labels"))
        values = data['operation'] == 'remove' ? labels - data['labels'] : (labels + data['labels']).uniq
        guard!
        @client.call(:post, "conversations/#{@session.conversation_id}/labels", { labels: values })
      when 'assign' then assign(data)
                         return
      when 'status'
        status(data['status'])
        return if data['status'] != 'pending'
      when 'end' then finish!
                      return
      else raise JrcFlows::WorkflowEngine::Error, "Bloco remoto não suportado: #{type}"
      end
      advance(node, port)
      @session.save!
    end
  end

  def current_node
    @flow.graph['nodes'].find { |node| node['id'] == @session.node_id }
  end

  def advance(node, port)
    @session.node_id = @flow.graph['edges'].find { |edge| edge['source'] == node['id'] && edge['port'] == port }&.fetch('target')
  end

  def send_message(text, private_note: false)
    guard!
    @client.message(@session.conversation_id, text.to_s.first(10_000), private_note: private_note)
  end

  def assign(data)
    guard!
    body = {}
    body[:team_id] = data['team_id'].to_i if data['team_id'].present?
    body[:assignee_id] = data['agent_id'].to_i if data['agent_id'].present?
    @client.call(:post, "conversations/#{@session.conversation_id}/assignments", body)
    @client.call(:post, "conversations/#{@session.conversation_id}/toggle_status", { status: 'open' })
    finish!
  end

  def status(value)
    guard!
    @client.call(:post, "conversations/#{@session.conversation_id}/toggle_status", { status: value })
    finish! unless value == 'pending'
  end

  def finish!
    @session.update!(status: 'completed', finished_at: Time.current, wake_at: nil)
  end

  def stop!(reason)
    @session&.update!(status: 'paused', error: reason, finished_at: Time.current, wake_at: nil)
  end

  def fail!(error)
    return unless @session && @session.reload.status == 'running'

    known = error.is_a?(JrcFlows::WorkflowEngine::Error) || error.is_a?(JrcFlows::ChatwootClient::Error)
    @session.update!(status: 'failed', error: known ? error.message.first(240) : 'Falha na execução remota.', finished_at: Time.current, wake_at: nil)
  end
end

JrcFlows::RemoteRunner.prepend(JrcFlows::OwnershipEntrypoints::RemoteRunner)

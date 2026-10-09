class JrcNico::OperatorSession
  class Busy < StandardError; end
  attr_reader :session, :access

  def initialize(account:, user:)
    @access = JrcNico::OperationalAccess.new(account: account, user: user).authorize!
    @session = JrcNico::Session.find_or_create_by!(account: account, user: user)
    check_history_access!
  end

  def ask(message:, request_id:, conversation_id: nil, prepared: nil, route_name: nil)
    command = nil
    existing = session.with_lock do
      existing = session.commands.find_by(request_id: request_id)
      if existing
        raise ArgumentError, 'Identificador já usado para outro pedido.' unless existing.message == message

        next existing
      end
      raise Busy if session.commands.where(status: 'planning').where('created_at > ?', 2.minutes.ago).exists?

      session.commands.where(source_notice_id: nil, status: %w[awaiting_confirmation browser_pending]).update_all(status: 'cancelled',
                                                                                                                  updated_at: Time.current)
      workflow = prepared ? nil : request_id
      session.update!(context: session.context.merge('active_workflow_id' => workflow))
      values = JrcNico::OperatorContext.command_context(workflow, conversation_id, route_name)
      command = session.commands.create!(request_id: request_id, message: message, execution_context: values)
      session.append('user', message)
      nil
    end
    return existing if existing

    if prepared
      prepare(command, prepared.fetch('tool'), prepared.fetch('arguments'))
    else
      plan(command, conversation_id)
    end
    command
  rescue StandardError => e
    fail_command(command, e) if command
    raise
  end

  def execute(command, delegation: nil)
    if delegation
      delegation.conversation.with_lock { execute_authorized(command, delegation: delegation) }
    else
      execute_authorized(command)
    end
  end

  def execute_authorized(command, delegation: nil)
    access.authorize!
    JrcNico::CustomerRequestScope.validate!(access, command.source_notice, command.arguments) if command.source_notice
    access.account.with_lock do
      session.with_lock do
        command.with_lock do
          next unless command.status == 'awaiting_confirmation'

          if command.created_at < 15.minutes.ago
            command.update!(status: 'cancelled', reply: 'A prévia expirou. Faça o pedido novamente para revisar os dados atuais.')
            next
          end
          authorization = { 'source' => 'operator', 'user_id' => access.user.id }
          if command.execution_context['explicit_operator_request'] == true
            authorization['mode'] = 'explicit_request'
            authorization['request_id'] = command.request_id
          end
          if delegation
            delegation.lock!
            raise Pundit::NotAuthorizedError unless JrcNico::DelegatedActions.permitted?(delegation, command, access)

            authorization.merge!('source' => 'delegation', 'delegation_id' => delegation.id, 'version' => delegation.version)
          end
          begin_execution!(command, authorization)
          result = JrcNico::ToolExecutor.new(access, command: command).call(command.tool, command.arguments)
          status = result.is_a?(Hash) && result[:browser_action] ? 'browser_pending' : 'succeeded'
          remember_result(command.tool, result, command: command, remember_selection: !command.source_notice)
          command.update!(status: status, result: result.as_json,
                          reply: result.is_a?(Hash) ? result[:message] : 'Ação concluída. Confira os resultados.')
          session.append('assistant', command.reply)
        end
      end
    end
    command
  rescue StandardError => e
    fail_command(command.reload, e)
    raise
  end

  def cancel(command)
    command.with_lock do
      command.update!(status: 'cancelled', reply: 'Ação cancelada.') if %w[awaiting_confirmation browser_pending].include?(command.status)
    end
    command
  end

  def browser_claim(command)
    if command.execution_context.dig('authorization', 'source') == 'delegation'
      command.source_notice.conversation.with_lock { claim_browser_action(command) }
    else
      claim_browser_action(command)
    end
  end

  def claim_browser_action(command)
    JrcNico::CustomerRequestScope.validate!(access, command.source_notice, command.arguments) if command.source_notice
    command.with_lock do
      raise Busy unless command.status == 'browser_pending'
      raise ArgumentError, 'Ação expirada. Prepare novamente.' if command.approved_at < 2.minutes.ago

      if command.execution_context.dig('authorization', 'source') == 'delegation'
        delegation = JrcNico::DelegatedActions.for_notice(command.source_notice)
        delegation&.lock!
        raise Pundit::NotAuthorizedError unless JrcNico::DelegatedActions.permitted?(delegation, command, access)
      end

      current_result = JrcNico::ToolExecutor.new(access, command: command).call(command.tool, command.arguments) # revalidate current permissions and channel
      if command.tool == 'call_contact' && current_result[:phone_number] != command.result['phone_number']
        raise ArgumentError, 'O telefone do contato mudou. Prepare a ligação novamente para revisar o destinatário.'
      end

      command.update!(status: 'executing')
    end
    command
  end

  def browser_result(command, status, detail)
    session.with_lock do
      command.with_lock do
        raise Busy unless command.status == 'executing' && command.result['browser_action']
        raise ArgumentError, 'Estado inválido.' unless %w[succeeded failed unknown].include?(status)

        command.update!(status: status, result: command.result.merge('browser_status' => status, 'browser_detail' => detail.to_s.first(500)),
                        reply: detail.to_s.first(500))
        session.append('assistant', "#{command.reply} (estado informado pela aba do operador)")
      end
    end
    command
  end

  def plan_customer_request(command, notice)
    plan(command, notice.conversation.display_id, notice: notice)
  rescue StandardError => e
    fail_command(command, e)
    raise
  end

  def continue_workflow(previous)
    workflow_id = previous.execution_context['workflow_id']
    return unless workflow_id && previous.status == 'succeeded'

    command = session.with_lock do
      next unless session.context['active_workflow_id'] == workflow_id

      steps = session.commands.where("execution_context ->> 'workflow_id' = ?", workflow_id)
      next if steps.where("execution_context ->> 'continuation_of' = ?", previous.id.to_s).exists?
      next if steps.where(status: %w[planning awaiting_confirmation browser_pending executing unknown failed cancelled]).exists?

      if steps.count >= 12
        session.append('assistant', 'O pedido atingiu doze etapas. Confira os resultados antes de continuar.')
        next
      end
      values = JrcNico::OperatorContext.continuation_context(previous)
      session.commands.create!(request_id: SecureRandom.uuid, message: previous.message, execution_context: values)
    end
    plan(command, command.execution_context['conversation_id']) if command
  rescue StandardError => e
    fail_command(command, e) if command
    raise
  end

  private

  private :execute_authorized, :claim_browser_action

  def check_history_access!
    digest = JrcNico::OperatorContext.access_digest(access)
    allowed = session.context['access_digest'] == digest
    if allowed
      allowed = Array(session.context['conversation_ids']).all? do |id|
        access.conversation(id)
        true
      rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
        false
      end
      allowed &&= Array(session.context['resources']).all? do |type, id|
        case type
        when 'Contact' then access.contact(id)
        when 'JrcCrm::Lead' then access.crm_scope(JrcCrm::Lead).find(id)
        when 'JrcCrm::Deal' then access.crm_scope(JrcCrm::Deal).find(id)
        when 'JrcCrm::Proposal' then access.crm_scope(JrcCrm::Proposal).find(id)
        when 'JrcCrm::Activity' then access.crm_scope(JrcCrm::Activity, owner: :user_id).find(id)
        when 'AutomationRule'
          rule = access.account.automation_rules.find(id)
          raise Pundit::NotAuthorizedError unless access.account.feature_enabled?('automations') && access.policy(rule).show?
        when 'JrcCampaigns::Campaign'
          raise Pundit::NotAuthorizedError unless access.campaigns?

          access.account.jrc_campaigns.find(id)
        when 'JrcNico::KnowledgeDocument' then JrcNico::KnowledgeDocument.where(account: access.account).approved.find(id)
        else
          JrcNico::DomainAccess.authorize_resource!(access, type, id) if JrcNico::DomainAccess::RESOURCE_TYPES.include?(type)
        end
        true
      rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
        false
      end
      notices = JrcNico::Notice.where(id: session.commands.where('created_at >= ?', session.context['visible_since'])
                                               .where.not(source_notice_id: nil).select(:source_notice_id)).includes(:commands, :conversation)
      allowed &&= notices.all? { |notice| notice.visible_to?(access) }
    end
    return if allowed

    session.with_lock do
      session.update!(messages: [], context: { access_digest: digest, visible_since: Time.current.iso8601(6) })
      session.commands.where(status: %w[awaiting_confirmation browser_pending]).update_all(status: 'cancelled', updated_at: Time.current)
    end
  end

  def plan(command, conversation_id, notice: nil)
    resolve_recipient_choice(command) unless notice
    catalog = JrcNico::ToolCatalog.new(access)
    selected = conversation_id.present? ? access.conversation(conversation_id) : nil
    native_context = JrcNico::OperatorContext.new(access: access, session: session, selected: selected, notice: notice)
    native_context.remember_selection!
    context = {
      operator_id: access.user.id, tools: catalog.available, modules: JrcCopilot::TaskCatalog::ROUTE_GUIDES.transform_values { |v| v[:title] },
      current_module: JrcCopilot::TaskCatalog::ROUTE_GUIDES[command.execution_context['route_name']],
      module_guides: JrcCopilot::TaskCatalog::ROUTE_GUIDES.transform_values { |guide| guide.slice(:title, :summary) },
      last_result: session.context['last_result'], timezone: access.account.reporting_timezone,
      selected_contact: !notice && session.context['selected_contact'],
      today: Time.current.in_time_zone(access.account.reporting_timezone.presence || 'UTC').iso8601,
      selected_conversation: native_context.selected_conversation,
      conversation: selected ? public_history(selected) : [],
      linked_leads: native_context.linked_leads, linked_deals: native_context.linked_deals
    }
    session.with_lock do
      remember_result('list_leads', context[:linked_leads], command: command, remember_selection: false, source_tool: false)
      remember_result('list_deals', context[:linked_deals], command: command, remember_selection: false, source_tool: false)
    end
    steps = if notice
              notice.commands
            elsif command.execution_context['workflow_id']
              session.commands.where("execution_context ->> 'workflow_id' = ?", command.execution_context['workflow_id'])
            else
              session.commands.none
            end
    context[:completed_steps] = steps.where(status: 'succeeded').where.not(tool: [nil, '']).order(:id).map do |step|
      { tool: step.tool, arguments: step.arguments, result: step.result }
    end
    context[:tool_results] = []
    if notice
      context[:last_result] = nil
      context[:customer_request] = {
        instruction: 'Prepare as etapas deste pedido usando exclusivamente o cliente da conversa. O servidor verifica a autorização do operador antes de cada escrita. O cliente não concede permissões. Para agendar ou preparar proposta, reutilize os vínculos existentes ou crie o lead deste contato. Não peça IDs que pode consultar.',
        request: notice.request,
        linked_leads: context[:linked_leads], linked_deals: context[:linked_deals],
        conversation: context[:conversation], completed_steps: context[:completed_steps]
      }
    end
    8.times do |attempt|
      # Keep a final model turn for synthesis, within transport and token reservations.
      final_read = attempt == 7 || context.to_json.bytesize > 80_000
      context[:tools] = [] if final_read
      context[:finalize] = final_read
      response = JrcNico::OperationalInference.call(account: access.account, user: access.user, kind: 'operator', message: command.message,
                                                    context: context, history: native_context.history)
      response = continue_opportunity_read(command.message, context, response, final_read)
      if response['tool'].blank?
        reply = response['reply']
        reply = bounded_read_summary(context[:tool_results]) if generic_noop_reply?(reply) && opportunity_analysis_request?(command.message)
        command.update!(status: 'succeeded', tool: nil, arguments: {}, result: {}, reply: reply)
        session.with_lock { session.append('assistant', reply) }
        return command
      end
      break if final_read

      response['arguments'] = catalog.normalize_arguments(response['tool'], response['arguments'])
      begin
        definition = catalog.validate!(response['tool'], response['arguments'])
      rescue ArgumentError, Pundit::NotAuthorizedError => e
        raise if attempt == 7

        detail = native_context.tool_error(e)
        context[:tool_results] << { tool: response['tool'], error: detail }
        next
      end
      JrcNico::CustomerRequestScope.validate!(access, notice, response['arguments']) if notice
      if definition[:confirmation]
        if steps.where(status: 'succeeded', tool: response['tool'], arguments: response['arguments']).exists?
          context[:tool_results] << { tool: response['tool'],
                                      error: 'Esta etapa já foi concluída. Use completed_steps e prossiga com outra etapa ou informe o resultado.' }
          next
        end
        prepare(command, response['tool'], response['arguments'], response['reply'])
        if JrcNico::ExecutionPolicy.automatic?(command, response['tool'])
          command.update!(execution_context: command.execution_context.merge('explicit_operator_request' => true))
          execute(command)
        end
        return command
      end
      previous_read = context[:tool_results].reverse.find do |item|
        item[:result] && item[:tool] == response['tool'] && item[:arguments] == response['arguments']
      end
      if previous_read
        if response['tool'] == 'count_contacts' && command.message.match?(/\A\s*(?:quantos contatos(?: temos(?: cadastrados)?)?|conte os contatos)[?.!]?\s*\z/i)
          reply = readable_read_summary(response['tool'], previous_read[:result])
          command.update!(status: 'succeeded', tool: response['tool'], arguments: response['arguments'],
                          result: previous_read[:result].as_json, reply: reply)
          session.with_lock { session.append('assistant', reply) }
          return command
        end
        context[:tool_results] << { tool: response['tool'], arguments: response['arguments'],
                                    error: 'Consulta idêntica já concluída. Use o resultado existente e prossiga sem repeti-la.' }
        next
      end
      result = JrcNico::ToolExecutor.new(access, customer_notice: notice, command: command).call(response['tool'], response['arguments'])
      command.update!(tool: response['tool'], arguments: response['arguments'], result: result.as_json)
      session.with_lock { remember_result(response['tool'], result, command: command, remember_selection: !notice) }
      if %w[open_module open_conversation analyze_conversation_sentiment].include?(response['tool'])
        command.update!(status: 'succeeded', reply: result[:message])
        session.with_lock { session.append('assistant', command.reply) }
        return command
      end
      context[:tool_results] << { tool: response['tool'], arguments: response['arguments'], result: result }
      next unless response['tool'] == 'search_contacts' && result.size > 1

      session.with_lock do
        session.update!(context: session.context.merge('ambiguous_contact_ids' => result.map { |row| row['id'] }, 'selected_contact' => nil))
      end
      command.update!(status: 'succeeded', reply: contact_choices(result))
      session.with_lock { session.append('assistant', command.reply) }
      return command
    end
    command.update!(status: 'succeeded', reply: bounded_read_summary(context[:tool_results]))
    session.with_lock { session.append('assistant', command.reply) }
  end

  def contact_choices(rows)
    options = rows.map do |row|
      channels = Array(row[:conversations] || row['conversations']).map do |conversation|
        (conversation[:channel] || conversation['channel']).to_s.delete_prefix('Channel::')
      end.uniq
      "#{row['name']}; telefone #{row['phone_number'].presence || 'não cadastrado'}; " \
        "email #{row['email'].presence || 'não cadastrado'}; conversas visíveis: #{channels.join(', ').presence || 'nenhuma na amostra'}."
    end
    "Encontrei mais de um contato. Escolha pelo nome completo, telefone ou email.\n#{options.join("\n")}"
  end

  def resolve_recipient_choice(command)
    contacts = Array(session.context['ambiguous_contact_ids']).map { |id| access.contact(id) }
    return if contacts.empty?

    matches = JrcNico::RecipientChoice.match(command.message, contacts)
    previous = session.context['selected_contact']
    chosen = matches.one? ? matches.first : nil
    confirmation = command.message.to_s.strip.match?(/\A(?:sim|confirmo|pode ligar|sim pode ligar|pode enviar|confirmado)[.!\s]*\z/i)
    chosen ||= contacts.find { |contact| contact.id == previous['id'] } if matches.empty? && previous && confirmation
    snapshot = chosen&.slice(:id, :name, :email, :phone_number)
    session.with_lock { session.update!(context: session.context.merge('selected_contact' => snapshot)) }
  end

  def require_recipient_choice!(command, name, arguments)
    candidates = Array(session.context['ambiguous_contact_ids'])
    return if candidates.empty? || command.source_notice

    target_ids = [arguments['contact_id']].compact
    ids = Array(arguments['conversation_ids']) + [arguments['conversation_id']].compact
    target_ids += ids.map { |id| access.conversation(id).contact_id }
    { 'lead_id' => JrcCrm::Lead, 'deal_id' => JrcCrm::Deal }.each do |field, model|
      target_ids << access.crm_scope(model).find(arguments[field]).contact_id if arguments[field]
    end
    return if (target_ids & candidates).empty? && name != 'create_contact'

    resolve_recipient_choice(command)
    selected = [session.context.dig('selected_contact', 'id')].compact
    selected << access.conversation(command.execution_context['conversation_id']).contact_id if command.execution_context['conversation_id']
    return unless selected.uniq.size != 1 || target_ids.empty? || target_ids.any? { |id| id != selected.first }

    raise ArgumentError, 'Há contatos ambíguos. Escolha pelo nome completo, telefone ou email antes de preparar esta ação.'
  end

  def bounded_read_summary(results)
    successful = results.select { |item| item[:result] }.uniq { |item| [item[:tool], item[:arguments]] }
    batches = successful.select { |item| item[:tool] == 'conversation_opportunity_batch' }.map { |item| item[:result] }
    if batches.any?
      rows = batches.flat_map { |batch| batch[:conversations] }.uniq { |row| row[:conversation_id] }
      candidates = rows.first(20).map do |row|
        customer_text = Array(row[:messages]).reverse.find { |message| message[:message_type].to_s == 'incoming' }&.dig(:content)
        customer_text ||= Array(row[:messages]).last&.dig(:content)
        leads = Array(row[:lead_ids])
        "Conversa ##{row[:conversation_id]} — #{row[:contact_name]} — #{row[:channel]} — #{row[:status]}; " \
          "leads existentes: #{leads.presence&.join(', ') || 'nenhum na consulta'}; " \
          "contexto recente: #{customer_text.to_s.squish.first(180).presence || 'sem mensagem pública no lote'}."
      end
      omitted = rows.size - candidates.size
      continuation = batches.last[:next_page] ? "Próximo lote disponível: página #{batches.last[:next_page]}." : 'Fim da amostra visível.'
      return "Foram lidas #{rows.size} conversas visíveis, em todos os status, com até cinco mensagens públicas por conversa. " \
             "Abaixo estão candidatos para revisão comercial. Esta análise realizou somente consultas; nenhum lead foi criado sem confirmação.\n" \
             "#{candidates.join("\n")}\n" \
             "#{"Mais #{omitted} conversas foram lidas e não cabem nesta resposta. " if omitted.positive?}" \
             "#{batches.last[:scope]} #{continuation}"
    end
    return 'O NICO não recebeu resultados de consulta para apresentar.' if successful.empty?

    summaries = successful.map { |item| readable_read_summary(item[:tool], item[:result]) }.uniq
    "Concluí as consultas possíveis nesta rodada. #{summaries.join(' ')}".first(4000)
  end

  def readable_read_summary(tool, result)
    data = result.as_json
    case tool
    when 'count_contacts'
      "Há #{data['count']} contatos cadastrados na conta."
    when 'list_contacts'
      rows = JrcNico::OperatorContext.contact_rows(data)
      "Contatos encontrados: #{rows.join('; ').presence || 'nenhum'}."
    when 'list_conversations'
      rows = Array(data).map { |row| "##{row['conversation_id']} #{row['contact_name']} — #{row['channel']} — #{row['status']}" }
      "Conversas encontradas: #{rows.join('; ').presence || 'nenhuma'}."
    when 'read_conversation'
      "Conversa ##{data['conversation_id']} de #{data['contact_name']}, canal #{data['channel']}, status #{data['status']}; " \
      "#{Array(data['messages']).size} mensagens públicas lidas."
    when 'list_leads'
      rows = Array(data).map { |row| "lead ##{row['id']} #{row['name']} (status #{row['status']}, contato ##{row['contact_id']})" }
      "Leads encontrados: #{rows.join('; ').presence || 'nenhum'}."
    when 'list_deals'
      rows = Array(data).map { |row| "negócio ##{row['id']} #{row['title']} (status #{row['status']})" }
      "Negócios encontrados: #{rows.join('; ').presence || 'nenhum'}."
    else
      "#{tool}: #{data.to_json.first(1200)}"
    end
  end

  def continue_opportunity_read(message, context, response, final_read)
    return response unless opportunity_analysis_request?(message)
    return response if response['tool'].present? || final_read

    batches = context[:tool_results].select { |item| item[:tool] == 'conversation_opportunity_batch' && item[:result] }
    page = batches.empty? ? 1 : batches.last.dig(:result, :next_page)
    return response unless page
    return response if context.to_json.bytesize > 65_000

    { 'reply' => '', 'tool' => 'conversation_opportunity_batch', 'arguments' => { 'page' => page } }
  end

  def opportunity_analysis_request?(message)
    normalized = message.to_s.unicode_normalize(:nfkd).encode('ASCII', invalid: :replace, undef: :replace, replace: '').downcase
    normalized.match?(/(oportun|potencial).*(conversa|contato|lead)|(conversa|contato).*(oportun|potencial|gerar lead)/)
  end

  def generic_noop_reply?(reply)
    normalized = reply.to_s.unicode_normalize(:nfkd).encode('ASCII', invalid: :replace, undef: :replace, replace: '').downcase
    normalized.blank? || normalized.include?('consultei os dados disponiveis') || normalized.include?('selecione o registro')
  end

  def public_history(conversation)
    conversation.messages.where(private: false, message_type: [:incoming, :outgoing]).order(id: :desc).limit(30).reverse.map do |message|
      { role: message.incoming? ? 'customer' : 'assistant', content: message.content.to_s.first(1000) }
    end
  end

  def prepare(command, name, arguments, reply = nil)
    definition = JrcNico::ToolCatalog.new(access).validate!(name, arguments)
    raise ArgumentError, 'Esta ferramenta é de consulta.' unless definition[:confirmation]

    require_recipient_choice!(command, name, arguments)
    command.update!(tool: name, arguments: arguments, status: 'awaiting_confirmation', reply: reply.presence || definition[:description])
    session.with_lock { session.append('assistant', "Prévia: #{command.reply}") }
  end

  def remember_result(tool, result, command:, remember_selection: true, source_tool: true)
    data = result.as_json
    rows = data.is_a?(Array) ? data : data['items'] || data['conversations'] || [data]
    nested = rows.flat_map { |row| row.is_a?(Hash) ? Array(row['conversations']) : [] }
    ids = (rows + nested).filter_map { |row| row['conversation_id'] if row.is_a?(Hash) }
    ids += Array(data['conversation_ids']) if data.is_a?(Hash)
    types = { 'search_contacts' => 'Contact', 'list_contacts' => 'Contact', 'list_leads' => 'JrcCrm::Lead', 'list_deals' => 'JrcCrm::Deal',
              'list_activities' => 'JrcCrm::Activity', 'list_proposals' => 'JrcCrm::Proposal', 'list_automations' => 'AutomationRule',
              'list_campaigns' => 'JrcCampaigns::Campaign' }
    resources = rows.filter_map do |row|
      next unless row.is_a?(Hash)

      type = row['resource_type'] || types[tool]
      id = row.dig('record', 'id') || row['id']
      [type, id] if type && id
    end
    resources += rows.filter_map { |row| ['Contact', row['contact_id']] if row.is_a?(Hash) && row['contact_id'] }
    resources += Array(data['resources']) if data.is_a?(Hash)
    if tool == 'prepare_closed_case_knowledge'
      # The private draft stays in its exact Command/Approval receipt, never the approved global knowledge reader.
      resources = JrcNico::Helpdesk::GroupDraftActions.new(access, command).history_resources
    end
    command.update!(execution_context: JrcNico::OperatorContext.execution_context(command, tool, resources, ids, source_tool))
    context = session.context.merge('resources' => (Array(session.context['resources']) + resources).uniq,
                                    'conversation_ids' => (Array(session.context['conversation_ids']) + ids).uniq)
    context['last_result'] = { tool: tool, result: data } if remember_selection
    session.update!(context: context)
  end

  def begin_execution!(command, authorization)
    JrcNico::Helpdesk::ExecutionGuard.authorize!(access, command)
    command.update!(status: 'executing', approved_at: Time.current,
                    execution_context: command.execution_context.merge('authorization' => authorization))
  end

  def fail_command(command, error)
    detail = case error
             when ActiveRecord::RecordInvalid then error.record.errors.full_messages.join(', ')
             when ArgumentError then error.message
             when Pundit::NotAuthorizedError then 'Seu perfil não permite esta ação ou o acesso ao recurso mudou.'
             when ActiveRecord::RecordNotFound then 'Registro não encontrado no seu escopo. Busque novamente.'
             when JrcNico::RuntimeClient::Error
               workflow = command.execution_context['workflow_id']
               tools = JrcNico::ToolCatalog::TOOLS.select { |_name, definition| definition[2] }.keys
               previous_changes = workflow && session.commands.where("execution_context ->> 'workflow_id' = ?", workflow)
                                                     .exists?(status: 'succeeded', tool: tools)
               error.user_message(previous_changes: previous_changes)
             when JrcNico::RunCapacity::Exceeded then 'Limite de uso ou capacidade atingido. Aguarde ou revise os limites da conta.'
             else 'Não foi possível concluir. Verifique o estado do recurso antes de tentar novamente.'
             end
    command.update!(status: command.status == 'executing' ? 'unknown' : 'failed', reply: detail)
    session.with_lock { session.append('assistant', detail) }
  end
end

class JrcFlows::Actions
  def initialize(run)
    @run = run
    @conversation = run.conversation
    @account = run.account
    @evaluator = JrcFlows::Evaluator.new(run.variables)
  end

  def execute(type, data)
    JrcRelationship::PlaybookFlowContinuation.effect(@run, type, data) { execute_native(type, data) }
  end

  private

  def execute_native(type, data)
    case type
    when 'message', 'note' then send_message(@evaluator.render(data['text']), private_note: type == 'note')
    when 'media' then send_media(data)
    when 'variable' then @run.variables[data.fetch('variable')] = @evaluator.render(data['value'])
    when 'contact'
      @conversation.contact.update!(data.fetch('field') => @evaluator.render(data['value']))
      refresh_contact
    when 'labels'
      labels = Array(data['labels']).map { |label| @account.labels.find_by!(title: label).title }
      @conversation.update!(label_list: data['operation'] == 'remove' ? @conversation.label_list - labels : (@conversation.label_list + labels).uniq)
    when 'status' then @conversation.update!(status: data.fetch('status'))
    when 'assign' then assign(data)
    when 'create_lead' then @run.variables['lead_id'] = lead.id
    when 'move_deal' then move_deal(data)
    when 'activity' then create_activity(data)
    when 'webhook' then webhook(data)
    when 'nico' then delegate(data)
    else raise "Bloco não suportado: #{type}"
    end
  end

  def send_message(text, private_note: false, attachments: nil)
    Messages::MessageBuilder.new(nil, @conversation, {
                                   content: text, private: private_note, attachments: attachments,
                                   content_attributes: { jrc_flow_run_id: @run.id, jrc_flow_node_id: @run.node_id, jrc_flow_delivery: 'queued' }
                                 }).perform
  end

  def send_media(data)
    SafeFetch.fetch(data.fetch('url'), max_bytes: 10.megabytes,
                                       allowed_content_type_prefixes: %w[image/ audio/ video/],
                                       allowed_content_types: %w[application/pdf text/plain]) do |file|
      if JrcRelationship::PlaybookFlowContinuation.managed?(@run)
        # SafeFetch owns and closes its tempfile. Persist the native blob while
        # the IO is open so ActiveStorage after_commit never reopens a deleted path.
        blob = ActiveStorage::Blob.create_and_upload!(io: file.tempfile, filename: file.filename, content_type: file.content_type)
        next send_message(@evaluator.render(data['text']), attachments: [blob.signed_id])
      end

      upload = ActionDispatch::Http::UploadedFile.new(tempfile: file.tempfile, filename: file.filename, type: file.content_type)
      send_message(@evaluator.render(data['text']), attachments: [upload])
    end
  end

  def assign(data)
    if data['team_id'].present?
      @conversation.update!(team: @account.teams.find(data['team_id']))
    end
    if data['agent_id'].present?
      user = @account.users.find(data['agent_id'])
      allowed = @conversation.inbox.members.exists?(user.id) || @account.administrators.exists?(user.id)
      raise 'O atendente não participa desta caixa.' unless allowed

      Conversations::AssignmentService.new(conversation: @conversation, assignee_id: user.id).perform
    end
    @conversation.update!(status: 'open')
  end

  def refresh_contact
    @run.variables.merge!(@conversation.contact.attributes.slice('name', 'email', 'phone_number').transform_keys { |key| "contact.#{key}" })
  end

  def ensure_crm!
    raise 'CRM não está habilitado.' unless @account.feature_enabled?('jrc_crm')
  end

  def lead
    ensure_crm!
    return managed_lead if JrcRelationship::PlaybookFlowContinuation.managed?(@run)

    JrcCrm::ConversationLeadService.new(account: @account, conversation: @conversation, actor: @run.flow.created_by).call.fetch(:lead)
  end

  def managed_lead
    context = JrcRelationship::PlaybookFlowRunContext.new(@run).authorize!
    guard = JrcRelationship::PlaybookFlowMutationGuard.new(context.reference)
    existing = guard.native_lead
    return existing if existing

    result = JrcCrm::ConversationLeadService.new(account: @account, conversation: @conversation, actor: context.reference.context.user).call
    row = result.fetch(:lead)
    raise Pundit::NotAuthorizedError unless result.fetch(:created)

    row.update!(business_unit_id: context.reference.assignment.business_unit_id)
    guard.native_lead
  end

  def move_deal(data)
    ensure_crm!
    return managed_move_deal(data) if JrcRelationship::PlaybookFlowContinuation.managed?(@run)

    stage = JrcCrm::Stage.where(account: @account).find(data.fetch('stage_id'))
    deals = JrcCrm::Deal.where(account: @account, contact_id: @conversation.contact_id, pipeline_id: stage.pipeline_id, status: 'open')
    raise 'É necessário exatamente um negócio aberto neste funil para o contato.' unless deals.count == 1

    result = JrcCrm::DealPipelineService.new(deal: deals.first, stage: stage, actor: @run.flow.created_by).call
    raise result[:error] unless result[:success]
  end

  def managed_move_deal(data)
    reference = JrcRelationship::PlaybookFlowRunContext.new(@run).authorize!.reference
    deal, stage = JrcRelationship::PlaybookFlowMutationGuard.new(reference).native_deal(data)
    result = JrcCrm::DealPipelineService.new(deal: deal, stage: stage, actor: reference.context.user).call
    raise ArgumentError, 'playbook_flow_deal_move_failed' unless result.fetch(:success)

    @run.variables['deal_id'] = deal.id
  end

  def create_activity(data)
    user = @account.users.find(data.fetch('user_id'))
    reference = if JrcRelationship::PlaybookFlowContinuation.managed?(@run)
                  JrcRelationship::PlaybookFlowRunContext.new(@run).authorize!.reference
                end
    selected_lead = lead
    activity = JrcCrm::Activity.create!(
      account: @account, user: user, lead: selected_lead, contact: @conversation.contact, conversation: @conversation,
      title: @evaluator.render(data['title']), description: @evaluator.render(data['description']),
      activity_type: 'follow_up', due_at: data.fetch('hours', 24).to_i.clamp(1, 720).hours.from_now,
      **(reference ? { business_unit_id: reference.assignment.business_unit_id } : {})
    )
    @run.variables['lead_id'] = selected_lead.id if reference
    @run.variables['activity_id'] = activity.id
    return unless reference

    JrcCrm::AuditLoggerService.new(account: @account, event_type: 'activity_created', actor: reference.context.user,
                                  resource: activity, from_value: nil, to_value: activity.status,
                                  metadata: { source: 'relationship_playbook_flow', run_id: @run.id, node_id: @run.node_id,
                                              business_unit_id: reference.assignment.business_unit_id }).call
  end

  def webhook(data)
    # Only explicitly selected fields leave the application; never serialize a conversation.
    payload = { event: 'jrc.flow', flow_id: @run.flow_id, run_id: @run.id,
                conversation_id: @conversation.display_id, data: @evaluator.render(data['body']) }
    SafeFetch.fetch(data.fetch('url'), method: :post, body: payload.to_json, max_bytes: 100_000,
                                       headers: { 'Content-Type' => 'application/json', 'Idempotency-Key' => "jrc-flow-#{@run.id}-#{@run.node_id}" },
                                       validate_content_type: false, read_timeout: 10) do |result|
      @run.variables['webhook_response'] = result.tempfile.read.first(10_000)
    end
  end

  def delegate(data)
    return managed_delegate(data) if JrcRelationship::PlaybookFlowContinuation.managed?(@run)

    access = JrcNico::OperationalAccess.new(account: @account, user: @run.flow.created_by)
    JrcNico::DelegationService.new(access).start({
                                                   'conversation_ids' => [@conversation.display_id],
                                                   'objective' => @evaluator.render(data.fetch('objective')),
                                                   'hours' => data.fetch('hours', 2).to_i.clamp(1, 8),
                                                   'allowed_actions' => Array(data['allowed_actions']) & JrcNico::DelegatedActions::GROUPS.keys
                                                 })
    delegation = JrcNico::Delegation.find_by!(account: @account, conversation: @conversation, status: 'active')
    JrcNico::CustomerTurnJob.perform_later(delegation.id)
  end

  def managed_delegate(data)
    reference = JrcRelationship::PlaybookFlowRunContext.new(@run).authorize!.reference
    access = JrcNico::OperationalAccess.new(account: @account, user: reference.context.user)
    # Complete only this authorized terminal node in the same transaction. The
    # native delegation service still rejects every other live Flow and bot.
    @run.update!(status: 'completed', finished_at: Time.current, wake_at: nil)
    result = JrcNico::DelegationService.new(access).start(
      'conversation_ids' => [@conversation.display_id], 'objective' => @evaluator.render(data.fetch('objective')),
      'hours' => data.fetch('hours', 2), 'allowed_actions' => data.fetch('allowed_actions')
    )
    @run.variables['delegation_id'] = result.fetch(0).fetch(:id)
    @conversation.reload
    # The native Delegation after_commit callback owns first-turn/expiry jobs.
  end
end

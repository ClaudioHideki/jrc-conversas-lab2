class JrcNico::ToolExecutor
  def initialize(access, customer_notice: nil, command: nil)
    @access = access.authorize!
    @account, @user = access.account, access.user
    @customer_conversation = customer_notice && @access.conversation(customer_notice.conversation.display_id)
    @customer_notice, @command = customer_notice, command
  end

  def call(name, arguments)
    JrcNico::ToolCatalog.new(@access).validate!(name, arguments)
    if JrcNico::DomainToolCatalog::TOOLS.key?(name) || JrcNico::ModuleActions::PROJECT_TASK_TOOLS.include?(name)
      raise Pundit::NotAuthorizedError if @customer_notice || @command&.source_notice_id
    end
    if JrcNico::DomainToolCatalog::TOOLS.key?(name)
      return JrcNico::DomainActions.new(@access, command: @command).call(name, arguments)
    end
    return JrcNico::AutomationActions.new(@access).call(name, arguments) if JrcNico::AutomationActions::TOOLS.key?(name)
    return JrcNico::CommercialActions.new(@access).call(name, arguments) if JrcNico::CommercialActions::TOOLS.include?(name)
    return JrcNico::ModuleActions.new(@access).prepare(name, arguments) if JrcNico::ModuleActions::TOOLS.key?(name)

    @args = arguments
    # Dispatch is bounded by ToolCatalog, never by a model-supplied Ruby method.
    public_send(name)
  end

  def search_contacts
    query = "%#{ActiveRecord::Base.sanitize_sql_like(@args.fetch('query'))}%"
    scope = @account.contacts
    scope = scope.where(id: @customer_conversation.contact_id) if @customer_conversation
    scope.where('name ILIKE :q OR email ILIKE :q OR phone_number ILIKE :q', q: query).limit(20)
            .select { |c| @access.policy(c).show? }.map { |c| contact_snapshot(c) }
  end

  def list_contacts
    scope = @account.contacts
    scope = scope.where(id: @customer_conversation.contact_id) if @customer_conversation
    scope.order(id: :desc).limit(20)
         .select { |c| @access.policy(c).show? }.map { |c| contact_snapshot(c) }
  end

  def count_contacts
    scope = @account.contacts
    scope = scope.where(id: @customer_conversation.contact_id) if @customer_conversation
    { count: scope.find_each.count { |c| @access.policy(c).show? } }
  end

  def create_contact
    raise Pundit::NotAuthorizedError unless @access.policy(Contact).create?

    attrs = contact_attributes
    raise ArgumentError, 'Informe telefone com DDI/DDD ou email.' if attrs['phone_number'].blank? && attrs['email'].blank?

    # Account lock serializes duplicate checks from NICO commands.
    duplicates = @account.contacts.where(phone_number: attrs['phone_number']).where.not(phone_number: [nil, ''])
    duplicates = duplicates.or(@account.contacts.where(email: attrs['email']).where.not(email: [nil, '']))
    raise ArgumentError, 'Já existe um contato com esse telefone ou email. Busque e selecione o cadastro existente.' if duplicates.exists?

    record_result(@account.contacts.create!(attrs), 'Contato criado', 'contacts_dashboard_index')
  end

  def update_contact
    contact = @access.contact(@args.fetch('contact_id'), :update?)
    contact.update!(contact_attributes)
    record_result(contact, 'Contato atualizado', 'contacts_dashboard_index')
  end

  def list_conversations
    conversations = @customer_conversation ? [@customer_conversation] : @access.conversations
    conversations.select do |c|
      (@args['status'].blank? || c.status == @args['status']) &&
        (@args['query'].blank? || c.contact.name.to_s.downcase.include?(@args['query'].downcase))
    end.first(20).map { |c| conversation_snapshot(c) }
  end

  def conversation_opportunity_batch
    conversations = @customer_conversation ? [@customer_conversation] : @access.conversations
    conversations = conversations.select { |record| record.status == @args['status'] } if @args['status'].present?
    page = @args.fetch('page', 1)
    batch = conversations.slice((page - 1) * 10, 10) || []
    { scope: 'Amostra das 200 conversas recentes da conta, filtrada pelas permissões do operador; não representa todo o histórico.',
      visible_in_sample: conversations.size, page: page, next_page: page * 10 < conversations.size ? page + 1 : nil,
      statuses: @args['status'].presence || 'all', message_limit: 5,
      conversations: batch.map do |conversation|
        leads = @access.crm? ? @access.crm_scope(JrcCrm::Lead).where(contact_id: conversation.contact_id).limit(20).pluck(:id) : []
        conversation_snapshot(conversation).merge(lead_ids: leads,
          messages: conversation.messages.where(private: false, message_type: [:incoming, :outgoing]).order(id: :desc).limit(5).reverse.map do |message|
            { id: message.id, message_type: message.message_type, content: message.content.to_s.first(300), created_at: message.created_at }
          end)
      end }
  end

  def read_conversation
    conversation = @access.conversation(@args.fetch('conversation_id'))
    conversation_snapshot(conversation).merge(messages: conversation.messages.where(private: false).order(id: :desc).limit(30).reverse.map do |m|
      m.slice(:id, :message_type, :content, :status, :created_at)
    end)
  end

  def send_message
    conversation = @access.conversation(@args.fetch('conversation_id'))
    message = Messages::MessageBuilder.new(@user, conversation, @args.slice('content', 'private').symbolize_keys).perform
    { message: @args['private'] ? 'Nota interna registrada' : 'Mensagem registrada para envio pelo canal',
      id: message.id, status: message.status, conversation_id: conversation.display_id, route_name: 'home' }
  end

  def update_conversation
    conversation = @access.conversation(@args.fetch('conversation_id'))
    conversation.with_lock do
      JrcNico::DelegationService.stop(conversation, reason: 'operator_action')
      conversation.reload
      if @args['assignee_id']
        assignee = @account.users.find(@args['assignee_id'])
        raise ArgumentError, 'Responsável sem acesso à caixa.' unless @access.membership.administrator? || conversation.inbox.members.exists?(id: assignee.id)

        Conversations::AssignmentService.new(conversation: conversation, assignee_id: assignee.id).perform
      end
      conversation.team = @account.teams.find(@args['team_id']) if @args['team_id']
      conversation.label_list = @args['labels'] if @args.key?('labels')
      if @args['status']
        raise ArgumentError, 'Status inválido.' unless Conversation.statuses.key?(@args['status'])

        conversation.status = @args['status']
      end
      conversation.priority = @args['priority'] if @args['priority']
      conversation.snoozed_until = parse_time(@args['snoozed_until']) if @args['snoozed_until']
      conversation.save!
    end
    conversation_snapshot(conversation).merge(message: 'Conversa atualizada')
  end

  def list_team
    { users: @account.users.limit(100).map { |u| u.slice(:id, :name) }, teams: @account.teams.limit(100).map { |t| t.slice(:id, :name) } }
  end

  def search_knowledge
    JrcNico::KnowledgeDocument.where(account: @account).approved
      .where("to_tsvector('portuguese', title || ' ' || body) @@ plainto_tsquery('portuguese', ?)", @args.fetch('query'))
      .limit(5).map { |d| { id: d.id, resource_type: d.class.name, title: d.title, body: d.body.first(4000) } }
  end

  def delegate_conversations
    delegations = JrcNico::DelegationService.new(@access).start(@args)
    { message: "Atendimento temporário delegado em #{delegations.size} conversa(s). Nenhuma regra recorrente foi criada.",
      operation_kind: 'temporary_delegation', conversations: delegations }
  end

  def take_over
    @args.fetch('conversation_ids').map do |id|
      conversation = @access.conversation(id)
      JrcNico::DelegationService.stop(conversation, reason: 'human_takeover', user: @user)
      conversation_snapshot(conversation).merge(message: 'Atendimento devolvido ao operador')
    end
  end

  def list_leads
    scope = @access.crm_scope(JrcCrm::Lead)
    scope = scope.where(contact_id: @customer_conversation.contact_id) if @customer_conversation
    scope = scope.where(contact_id: @access.contact(@args['contact_id']).id) if @args['contact_id']
    search(scope, 'name').map { |r| r.slice(:id, :name, :status, :contact_id, :notes) }
  end

  def create_lead
    if @args['conversation_id']
      conversation = @access.conversation(@args['conversation_id'])
      result = JrcCrm::ConversationLeadService.new(account: @account, actor: @user, conversation: conversation).call
      lead = result.fetch(:lead)
      @access.crm_scope(JrcCrm::Lead).find(lead.id)
      attrs = @args.slice('name', 'company_name', 'email', 'phone', 'notes')
      lead.update!(attrs) if result.fetch(:created) && attrs.any?
    else
      contact = @access.contact(@args['contact_id']) if @args['contact_id']
      attrs = @args.slice('name', 'company_name', 'email', 'phone', 'notes')
      attrs['name'] ||= contact&.name
      attrs['email'] ||= contact&.email
      attrs['phone'] ||= contact&.phone_number
      existing = contact && @access.crm_scope(JrcCrm::Lead).where(contact_id: contact.id).limit(21).to_a
      if existing && existing.size > 1
        raise ArgumentError, "Há vários leads para este contato. Selecione o ID: #{existing.map(&:id).join(', ')}."
      end
      lead = existing&.first || @account.jrc_crm_leads.create!(attrs.merge(contact: contact, owner: @user, source: 'nico'))
    end
    record_result(lead, 'Lead criado ou reutilizado', 'crm_leads')
  end

  def update_lead
    lead = @access.crm_scope(JrcCrm::Lead).find(@args.fetch('lead_id'))
    raise ArgumentError, 'Use a conversão para converter um lead.' if @args['status'] && !%w[new in_contact qualified unqualified].include?(@args['status'])

    lead.update!(@args.except('lead_id'))
    record_result(lead, 'Lead atualizado', 'crm_leads')
  end

  def convert_lead
    lead = @access.crm_scope(JrcCrm::Lead).find(@args.fetch('lead_id'))
    result = JrcCrm::LeadConversionService.new(lead: lead, account: @account, actor: @user, params: @args.except('lead_id').symbolize_keys).call
    raise ArgumentError, result[:error].to_s unless result[:success]

    record_result(result[:deal], 'Lead convertido em negócio', 'crm_deals')
  end

  def list_deals
    scope = @access.crm_scope(JrcCrm::Deal)
    scope = scope.where(contact_id: @customer_conversation.contact_id) if @customer_conversation
    search(scope, 'title').map { |r| r.slice(:id, :title, :status, :stage_id, :pipeline_id, :value_cents, :contact_id) }
  end

  def list_pipelines
    @account.jrc_crm_pipelines.limit(20).map { |p| p.slice(:id, :name).merge(stages: p.stages.map { |s| s.slice(:id, :name, :is_won, :is_lost) }) }
  end

  def move_deal
    deal = @access.crm_scope(JrcCrm::Deal).find(@args.fetch('deal_id'))
    stage = @account.jrc_crm_stages.find(@args.fetch('stage_id'))
    if stage.is_lost?
      deal.lost_reason = @account.jrc_crm_lost_reasons.find(@args.fetch('lost_reason_id'))
      deal.lost_reason_note = @args['lost_reason_note']
    end
    result = JrcCrm::DealPipelineService.new(deal: deal, stage: stage, actor: @user).call
    raise ArgumentError, result[:error].to_s unless result[:success]

    record_result(result[:deal], 'Etapa atualizada', 'crm_deals')
  end

  def list_activities
    scope = @access.crm_scope(JrcCrm::Activity, owner: :user_id)
    if @customer_conversation
      leads = @access.crm_scope(JrcCrm::Lead).where(contact_id: @customer_conversation.contact_id).select(:id)
      deals = @access.crm_scope(JrcCrm::Deal).where(contact_id: @customer_conversation.contact_id).select(:id)
      scope = scope.where(lead_id: leads).or(scope.where(deal_id: deals))
    end
    scope = scope.where(@args.slice('lead_id', 'deal_id'))
    scope.order(due_at: :asc).limit(30).map { |r| r.slice(:id, :title, :due_at, :status, :lead_id, :deal_id) }
  end

  def create_activity
    lead = @access.crm_scope(JrcCrm::Lead).find(@args['lead_id']) if @args['lead_id']
    deal = @access.crm_scope(JrcCrm::Deal).find(@args['deal_id']) if @args['deal_id']
    due_at = parse_time(@args.fetch('due_at'))
    raise ArgumentError, 'Informe uma data e horário futuros para a reunião.' if @args['activity_type'] == 'meeting' && due_at <= Time.current
    if @args['activity_type'] == 'meeting' && @account.jrc_crm_activities.where(user: @user, activity_type: 'meeting', status: 'scheduled', due_at: due_at).exists?
      raise ArgumentError, 'Já existe uma reunião do operador neste horário. Confirme outro horário antes de agendar.'
    end
    activity = @account.jrc_crm_activities.new(@args.slice('title', 'activity_type', 'description').merge(
      user: @user, lead: lead, deal: deal, due_at: due_at))
    result = JrcCrm::ActivityDispatchService.new(activity: activity, actor: @user).call
    raise ArgumentError, result[:error].to_s unless result[:success]

    record_result(activity, 'Atividade agendada; nenhum convite externo foi enviado', 'crm_activities')
  end

  def update_activity
    activity = @access.crm_scope(JrcCrm::Activity, owner: :user_id).find(@args.fetch('activity_id'))
    attrs = @args.except('activity_id', 'due_at')
    attrs['due_at'] = parse_time(@args['due_at']) if @args['due_at']
    attrs['completed_at'] = @args['status'] == 'completed' ? Time.current : nil if @args['status']
    activity.update!(attrs)
    record_result(activity, 'Atividade atualizada', 'crm_activities')
  end

  def list_products
    search(@account.jrc_crm_products.where(active: true), 'name').map do |product|
      product.slice(:id, :name, :description, :active, :unit_price_cents, :currency, :billing_model, :minimum_quantity,
                    :setup_fee_cents, :scope_included, :scope_excluded, :sales_unit)
    end
  end

  def create_proposal
    deal = @access.crm_scope(JrcCrm::Deal).find(@args.fetch('deal_id'))
    proposal = JrcCrm::ProposalBuilderService.new(deal: deal, actor: @user).call
    record_result(proposal, 'Proposta preparada para revisão e aprovação no CRM', 'crm_proposals').tap do |result|
      result[:record]['items'] = proposal.proposal_items.map { |item| item.attributes.slice('id', 'product_id', 'name_snapshot', 'quantity', 'unit_price_cents') }
    end
  end

  def list_proposals
    scope = @access.crm_scope(JrcCrm::Proposal)
    if @customer_conversation
      scope = scope.where(deal_id: @access.crm_scope(JrcCrm::Deal).where(contact_id: @customer_conversation.contact_id).select(:id))
    end
    scope = scope.where(deal_id: @access.crm_scope(JrcCrm::Deal).find(@args['deal_id']).id) if @args['deal_id']
    search(scope, 'title').map { |r| r.slice(:id, :title, :deal_id, :status, :total_cents, :valid_until) }
  end

  def read_proposal
    proposal = @access.crm_scope(JrcCrm::Proposal).find(@args.fetch('proposal_id'))
    record_result(proposal, 'Proposta consultada', 'crm_proposals').merge(
      details: proposal.slice(:title, :solution_description, :status, :approval_status, :total_cents, :monthly_cents,
                              :implementation_cents, :valid_until, :term_months),
      items: proposal.proposal_items.map { |item| item.slice(:id, :product_id, :name_snapshot, :quantity, :unit_price_cents, :billing_model, :total_cents) })
  end

  def list_campaigns
    @account.jrc_campaigns.order(updated_at: :desc).limit(20).map { |c| c.slice(:id, :name, :status, :review_digest, :review_snapshot, :approved_at) }
  end

  def create_campaign
    inbox = @account.inboxes.find(@args.fetch('inbox_id'))
    raise Pundit::NotAuthorizedError unless @access.inbox_visible?(inbox)

    campaign = @account.jrc_campaigns.create!(@args.merge(created_by: @user, trigger_type: 'manual', audience_type: 'all_contacts'))
    record_result(campaign, 'Rascunho criado; revise público, consentimentos e conteúdo antes de aprovar', 'jrc_campaigns_index')
  end

  def campaign_action
    campaign = @account.jrc_campaigns.find(@args.fetch('campaign_id'))
    actions = { 'request_review' => :request_review!, 'launch' => :launch!, 'pause' => :pause!, 'resume' => :resume!, 'cancel' => :cancel! }
    method = actions.fetch(@args.fetch('action')) { raise ArgumentError, 'Ação de campanha não permitida.' }
    campaign.public_send(method)
    record_result(campaign.reload, 'Estado da campanha atualizado', 'jrc_campaigns_index')
  end

  def campaign_report
    JrcCampaigns::ReportService.new(@account.jrc_campaigns.find(@args.fetch('campaign_id')), page: 1, per_page: 20).as_json
  end

  def operational_report
    conversations = @access.conversations
    result = { conversations: conversations.group_by(&:status).transform_values(&:length),
               scope: 'Até 200 conversas recentes visíveis ao operador', measured_at: Time.current.iso8601 }
    result[:activities] = @access.crm_scope(JrcCrm::Activity, owner: :user_id).group(:status).count if @access.crm?
    result
  end

  def channel_status
    { inboxes: @account.inboxes.select { |i| @access.inbox_visible?(i) }.map { |i| i.slice(:id, :name, :channel_type) },
      sip_configured: SipCredential.where(account_id: @account.id, user_id: @user.id, enabled: true).exists?,
      video_configured: VideoConferenceSetting.where(account_id: @account.id, user_id: @user.id).where.not(moderator_url: [nil, '']).exists? }
  end

  def call_contact
    contact = @access.contact(@args.fetch('contact_id'))
    raise ArgumentError, 'O contato não tem telefone cadastrado.' if contact.phone_number.blank?
    raise ArgumentError, 'Configure e habilite seu ramal antes de ligar.' unless channel_status[:sip_configured]

    { browser_action: 'sip_call', contact_id: contact.id, name: contact.name, phone_number: contact.phone_number,
      message: 'Destinatário validado. Inicie a ligação nesta aba.' }
  end

  def call_control
    raise ArgumentError, 'Controle inválido.' unless %w[answer reject hangup mute unmute hold unhold transfer].include?(@args['action'])
    raise ArgumentError, 'Informe o destino da transferência.' if @args['action'] == 'transfer' && @args['destination'].blank?

    { browser_action: 'sip_control', **@args.symbolize_keys }
  end

  def open_video
    raise ArgumentError, 'Configure sua sala de videoconferência antes de abrir.' unless channel_status[:video_configured]

    { browser_action: 'video', message: 'Sala disponível para abrir nesta aba.' }
  end

  def open_module
    name = @args.fetch('route_name')
    raise ArgumentError, 'Módulo desconhecido.' unless JrcCopilot::TaskCatalog::ROUTE_GUIDES.key?(name)

    { route_name: name, message: "Abrir #{JrcCopilot::TaskCatalog::ROUTE_GUIDES[name][:title]}" }
  end

  def account_profile
    @account.slice(:id, :name, :locale, :support_email, :reporting_timezone)
  end

  def set_reporting_timezone
    raise ArgumentError, 'Fuso horário inválido.' unless Time.find_zone(@args.fetch('timezone'))

    @account.update!(reporting_timezone: @args.fetch('timezone'))
    { message: "Fuso da agenda e dos relatórios atualizado para #{@account.reporting_timezone}.", route_name: 'general_settings_index' }
  end

  private

  def contact_attributes
    @args.slice('name', 'email', 'phone_number').tap do |attrs|
      attrs['email'] = attrs['email'].strip.downcase if attrs['email']
      attrs['phone_number'] = attrs['phone_number'].gsub(/[\s().-]/, '') if attrs['phone_number']
    end
  end

  def search(scope, column)
    scope = scope.where("#{column} ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(@args['query'])}%") if @args['query'].present?
    scope.order(updated_at: :desc).limit(20)
  end

  def record_result(record, message, route)
    { message: "#{message}: #{record.attributes['name'] || record.attributes['title']} (##{record.id})", resource_type: record.class.name, record: record.attributes.slice('id', 'name', 'title', 'status', 'phone_number', 'email',
      'contact_id', 'lead_id', 'deal_id', 'due_at', 'total_cents'), route_name: route }
  end

  def contact_snapshot(contact)
    conversations = @account.conversations.where(contact_id: contact.id).order(updated_at: :desc).limit(20)
                            .select { |record| @access.policy(record).show? }
    contact.slice(:id, :name, :email, :phone_number).merge(conversations: conversations.map { |record| conversation_snapshot(record) })
  end

  def conversation_snapshot(conversation)
    { conversation_id: conversation.display_id, contact_id: conversation.contact_id, contact_name: conversation.contact.name,
      phone_number: conversation.contact.phone_number, updated_at: conversation.updated_at, assignee_id: conversation.assignee_id,
      inbox_name: conversation.inbox.name, status: conversation.status, inbox_id: conversation.inbox_id, channel: conversation.inbox.channel_type }
  end

  def parse_time(value)
    zone = Time.find_zone(@account.reporting_timezone) || Time.zone
    zone.parse(value).tap { |time| raise ArgumentError, 'Data/hora inválida.' unless time }
  end
end

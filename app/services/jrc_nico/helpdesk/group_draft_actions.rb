# frozen_string_literal: true

# Only commands stamped by the existing HelpDesk Approval/ExecutionGuard may create these drafts.
class JrcNico::Helpdesk::GroupDraftActions
  TOOLS = { 'prepare_incident_campaign' => ['campaign', JrcNico::Helpdesk::GroupNativeCampaign],
    'prepare_closed_case_knowledge' => ['knowledge', JrcNico::Helpdesk::GroupNativeKnowledge] }.freeze

  def initialize(access, command)
    @command = command
    @context = JrcNico::Helpdesk::Context.new(access.membership).administrator!
    raise Pundit::NotAuthorizedError unless command&.persisted? && command.session.user_id == @context.member.user_id

    @approval = JrcNico::Helpdesk::Approval.where(account: access.account, command: command, approver: @context.member)
      .find_by!(event_id: command.execution_context.fetch('helpdesk_event_id'))
    @event = @context.event(@approval.event_id)
    refresh_sources!
  end

  def call
    raise Pundit::NotAuthorizedError unless @approval.state == 'executing' && @command.status == 'executing'

    @command.tool == 'prepare_incident_campaign' ? create_campaign : create_knowledge
  end

  def authorize_result!
    row = @command.tool == 'prepare_incident_campaign' ? campaign_result : knowledge_result
    proof = @command.result.fetch('provenance')
    raise Pundit::NotAuthorizedError unless proof == provenance(row)

    [[row.class.name, row.id]]
  rescue KeyError, ArgumentError, ActiveRecord::RecordNotFound
    raise Pundit::NotAuthorizedError
  end

  def history_resources
    raise Pundit::NotAuthorizedError unless @command.tool == 'prepare_closed_case_knowledge'

    scope = @approval.scope.fetch('group')
    JrcNico::Helpdesk::GroupActionPreview.authorize_saved_sources!(@context, scope, event: @event)
    scope.fetch('resources')
  end

  private

  def create_campaign
    @native.cohort.incident.with_lock do
      @native.cohort.tickets.each(&:lock!)
      @native.cohort.contacts.each(&:lock!)
      refresh_sources!

      existing = @context.account.jrc_campaigns.where("metadata -> 'nico_helpdesk' ->> 'event_id' = ?", @event.id.to_s).exists?
      raise ArgumentError, 'Incident event already has a native campaign draft' if existing

      list = JrcCampaigns::Sanitizer.new(account: @context.account, user: @context.member.user,
        name: @command.arguments.fetch('name'), entries: @native.cohort.entries).perform
      row = @context.account.jrc_campaigns.create!(name: @command.arguments.fetch('name'), created_by: @context.member.user,
        status: 'draft', trigger_type: 'manual', audience_type: 'sanitized_list', inbox_id: nil,
        audience_config: { 'sanitized_list_id' => list.id }, metadata: { 'nico_helpdesk' => draft_origin })
      row.campaign_inboxes.create!(inbox: @native.inbox, enabled: false)
      result(row, 'jrc_campaigns_index')
    end
  end

  def create_knowledge
    @native.ticket.with_lock do
      refresh_sources!

      row = JrcNico::KnowledgeDocument.create!(account: @context.account, author: @context.member.user,
        title: @command.arguments.fetch('title'), body: @command.arguments.fetch('body'), customer_visible: false,
        approved_at: nil, approved_by: nil)
      result(row, 'jrc_nico_helpdesk')
    end
  end

  def campaign_result
    row = @context.account.jrc_campaigns.find(@command.result.fetch('id'))
    list = @context.account.jrc_campaign_sanitized_lists.find(row.audience_config.fetch('sanitized_list_id'))
    actual = list.entries.order(:id).map { |entry| [entry.name, entry.phone_number, entry.metadata] }
    expected = @native.cohort.entries.map { |entry| [entry.fetch('name'), entry.fetch('phone'), entry.except('name', 'phone')] }
    link = row.campaign_inboxes.find_by!(inbox_id: @native.inbox.id)
    valid = row.status == 'draft' && row.trigger_type == 'manual' && row.audience_type == 'sanitized_list' && row.inbox_id.nil? &&
      row.metadata == { 'nico_helpdesk' => draft_origin } && row.name == @command.arguments.fetch('name') &&
      row.created_by_id == @context.member.user_id && list.created_by_id == @context.member.user_id && actual == expected &&
      !link.enabled? && row.campaign_inboxes.count == 1 && row.approved_at.nil? && row.approved_by_id.nil?
    raise Pundit::NotAuthorizedError unless valid

    row
  end

  def knowledge_result
    row = JrcNico::KnowledgeDocument.where(account: @context.account).find(@command.result.fetch('id'))
    valid = row.author_id == @context.member.user_id && row.title == @command.arguments.fetch('title') &&
      row.body == @command.arguments.fetch('body') && !row.customer_visible? && row.approved_at.nil? && row.approved_by_id.nil?
    raise Pundit::NotAuthorizedError unless valid

    row
  end

  def draft_origin
    @native.source.merge('command_id' => @command.id, 'request_id' => @command.request_id, 'approval_id' => @approval.id,
      'source_digest' => @command.arguments.fetch('source_digest'))
  end

  def refresh_sources!
    key, klass = TOOLS.fetch(@command.tool)
    scope = @approval.scope.fetch('group')
    @native = klass.new(context: @context, event: @event, group_key: scope.fetch('group_key'), input: scope.fetch('input').fetch(key))
    raise Pundit::NotAuthorizedError unless @native.candidate.fetch(:arguments) == @command.arguments
  end

  def provenance(row)
    value = draft_origin.merge('record_digest' => JrcNico::Helpdesk::Definition.digest(row.attributes.except('updated_at').as_json))
    if row.is_a?(JrcCampaigns::Campaign)
      list = @context.account.jrc_campaign_sanitized_lists.find(row.audience_config.fetch('sanitized_list_id'))
      value['list_digest'] = JrcNico::Helpdesk::Definition.digest(list.entries.order(:id)
        .map { |entry| entry.attributes.slice('id', 'name', 'phone_number', 'normalized_phone', 'status', 'reason', 'metadata') })
    end
    value
  end

  def result(row, route)
    { resource_type: row.class.name, id: row.id, record: row.attributes.slice('id', 'name', 'title', 'status', 'customer_visible'),
      resources: [[row.class.name, row.id]], provenance: provenance(row), route_name: route,
      message: 'Human-reviewed native draft saved; no publication or dispatch.' }
  end
end

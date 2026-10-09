# frozen_string_literal: true

# Finite, operator-reviewed proposals into the existing HelpDesk Approval/OperatorSession.
class JrcNico::Helpdesk::GroupActionPreview
  SOURCE_RULES = {
    'A1' => %w[R16], 'A2' => %w[R16], 'A3' => %w[R16], 'A4' => %w[R16],
    'B1' => %w[R16], 'B2' => %w[R16], 'C1' => %w[R01 R02 R04 R07 R12], 'C2' => %w[R16],
    'D1' => %w[R16], 'D2' => %w[R08 R10 R11 R13 R16], 'E' => %w[R01 R02 R03 R13 R16]
  }.freeze
  INPUT_FIELDS = %w[query summary binding_id conversation_id check_broker_status classification handoff activity reply campaign knowledge].freeze
  CLASSIFICATION_FIELDS = %w[priority_id category_id ticket_type_id subcategory_id contract_id service_fields].freeze
  HANDOFF_FIELDS = %w[queue_id team_id assignee_account_user_id].freeze

  def initialize(context:, event:, group_key:, input: {})
    @context = context.refresh!
    @event = @context.event(event.id)
    @ticket = @context.ticket(@event.ticket_id)
    @group = group_key
    @input = input_contract(input)
    raise ArgumentError, 'Unknown HelpDesk group' unless SOURCE_RULES.key?(@group)
    raise Pundit::NotAuthorizedError unless SOURCE_RULES.fetch(@group).include?(@event.rule_key)
    raise Pundit::NotAuthorizedError unless @event.actor_id == @context.member.id

    validate_legal_group!
  end

  def call
    sources = JrcNico::Helpdesk::GroupEvidence.new(context: @context, event: @event, group_key: @group, input: @input).call
    attempts = recorded_attempts
    group = JrcNico::Helpdesk::Catalog.call.find { |item| item[:key] == @group }
    enabled = enabled?
    actions = JrcNico::Helpdesk::GroupActions.new(context: @context, event: @event, group_key: @group,
                                                  input: @input, state: { sources: sources, enabled: enabled, attempts: attempts }).call
    value = preview_payload(group, sources, attempts, actions, enabled)
    value[:form_fields] = sources[:form_fields] if sources[:form_fields]
    value[:broker] = sources[:broker] if sources[:broker]
    value[:draft_choices] = JrcNico::Helpdesk::GroupDraftChoices.new(@context, @event, @group, sources.fetch(:evidence)).call
    value.merge(preview_digest: JrcNico::Helpdesk::Definition.digest(value))
  end

  def preview_payload(group, sources, attempts, actions, enabled)
    { contract_version: 1, event_id: @event.id, group_key: @group, phase: group.fetch(:phase), enabled: enabled,
      executable: actions.any? { |action| action[:can_prepare] }, preview: true, persisted: false, automatic_execution: false,
      source: source_identity, attempts: { recorded: attempts, limit: 2, handoff_required: attempts >= 2 }, actions: actions }
      .merge(source_fields(group, sources))
  end

  def source_identity
    { ticket_id: @ticket.id, unit_id: @ticket.unit_id, company_id: @ticket.company_id,
      service_id: @ticket.service_id, rule_key: @event.rule_key }
  end

  def source_fields(group, sources)
    { evidence: sources.fetch(:evidence), resources: sources.fetch(:resources).uniq,
      missing: (group.fetch(:missing) + sources.fetch(:missing)).uniq, required_fields: sources.fetch(:required_fields) }
  end

  private :preview_payload, :source_identity, :source_fields

  def approval_scope(tool:, arguments:, preview_digest:)
    # Remote health observations are display-only. Revalidation never repeats I/O.
    raise ArgumentError, 'Prepare the local action without a remote status check' if @input['check_broker_status'] == true

    preview = call
    unless ActiveSupport::SecurityUtils.secure_compare(preview.fetch(:preview_digest), preview_digest.to_s)
      raise ArgumentError, 'Group preview or native evidence changed'
    end

    candidate = preview.fetch(:actions).find { |action| action[:tool] == tool && action[:arguments] == arguments }
    raise Pundit::NotAuthorizedError unless candidate && candidate[:can_prepare]

    { 'group_key' => @group, 'input' => @input, 'preview_digest' => preview.fetch(:preview_digest),
      'resources' => preview.fetch(:resources), 'evidence' => preview.fetch(:evidence) }.as_json
  end

  def validate_scope!(scope, tool:, arguments:)
    expected = approval_scope(tool: tool, arguments: arguments, preview_digest: scope.fetch('preview_digest'))
    raise Pundit::NotAuthorizedError unless expected == scope

    true
  end

  def self.authorize_saved_sources!(context, scope, event:)
    scope.fetch('resources').each { |type, id| authorize_saved_resource!(context, type, id) }
    authorize_saved_knowledge!(context, scope)
    authorize_saved_broker!(context, scope, event)
    JrcNico::Helpdesk::GroupNativeActions.new(context: context, event: event, group_key: scope.fetch('group_key'),
                                             input: scope.fetch('input')).evidence!({ resources: [], evidence: [] })
    true
  end

  def self.authorize_saved_resource!(context, type, id)
    if type == 'Contact'
      context.access.contact(id)
    elsif type == 'Conversation'
      conversation = context.account.conversations.find(id)
      context.access.conversation(conversation.display_id)
    else
      JrcNico::Helpdesk::GroupNativeActions.authorize_resource!(context, type, id)
    end
  end

  def self.authorize_saved_knowledge!(context, scope)
    scope.fetch('evidence').select { |row| row['kind'] == 'approved_native_knowledge' }.each do |row|
      document = JrcNico::KnowledgeDocument.where(account: context.account).approved.find(row.fetch('id'))
      raise Pundit::NotAuthorizedError unless document.digest == row.fetch('digest')
    end
  end

  def self.authorize_saved_broker!(context, scope, event)
    return unless scope['group_key'] == 'C2'

    JrcNico::Helpdesk::GroupEvidence.new(context: context, event: event, group_key: 'C2',
                                         input: scope.fetch('input').except('check_broker_status')).call
  end

  private_class_method :authorize_saved_resource!, :authorize_saved_knowledge!, :authorize_saved_broker!

  private

  def validate_legal_group!
    profile = JrcNico::Helpdesk::TicketProfile.find_by(account: @context.account, ticket: @ticket)
    legal = profile&.legal_risk? || profile&.case_kind == 'legal'
    raise Pundit::NotAuthorizedError if legal && @group != 'D2'
  end

  def enabled?
    @event.policy_version.reload.eligible?(@ticket, @context.member) &&
      @event.policy_version.definition.dig('rules', @event.rule_key, 'enabled') == true &&
      @event.policy_version.definition.dig('groups', @group, 'enabled') == true
  end

  def input_contract(input)
    values = JrcServiceDesk::Input.attributes(input, INPUT_FIELDS)
    validate_text_inputs!(values)
    validate_identifiers!(values)
    validate_broker_choice!(values)
    values['classification'] = native_attributes(values['classification'], CLASSIFICATION_FIELDS) if values.key?('classification')
    values['handoff'] = native_attributes(values['handoff'], HANDOFF_FIELDS) if values.key?('handoff')
    JrcNico::Helpdesk::GroupNativeActions::INPUT_FIELDS.each_key do |key|
      values[key] = JrcNico::Helpdesk::GroupNativeActions.input(key, values[key]) if values.key?(key)
    end
    values
  end

  def validate_text_inputs!(values)
    %w[query summary].each do |key|
      next unless values.key?(key)

      limit = key == 'query' ? 200 : 2000
      raise ArgumentError, 'Bounded group text required' unless values[key].is_a?(String) && values[key].size <= limit
    end
  end

  def validate_identifiers!(values)
    %w[binding_id conversation_id].each do |key|
      raise ArgumentError, 'Explicit group identifier required' if values.key?(key) && (!values[key].is_a?(Integer) || !values[key].positive?)

      JrcServiceDesk::Input.id(values[key]) if values.key?(key)
    end
  end

  def validate_broker_choice!(values)
    return unless values.key?('check_broker_status') && [true, false].exclude?(values['check_broker_status'])

    raise ArgumentError, 'Explicit broker read choice required'
  end

  def native_attributes(attributes, fields)
    values = JrcServiceDesk::Input.attributes(attributes, fields)
    values.each do |key, value|
      if key.end_with?('_id')
        raise ArgumentError, 'Explicit native catalogue identifier required' unless value.is_a?(Integer)

        JrcServiceDesk::Input.id(value)
      elsif JrcNico::DomainToolCatalog.valid_value?(key, value) != true
        raise ArgumentError, 'Invalid catalogue field answers'
      end
    end
    values
  end

  def recorded_attempts
    rows = JrcNico::Helpdesk::Approval.where(account: @context.account, state: 'succeeded')
                                      .joins(:event, :command).where(jrc_nico_helpdesk_events: { ticket_id: @ticket.id })
                                      .where(jrc_nico_commands: { tool: 'add_service_ticket_note' }).where("scope -> 'group' ->> 'group_key' = ?", @group)
    rows.count do |approval|
      note_id = approval.command.result.dig('record', 'id')
      next false unless note_id && approval.command.status == 'succeeded'

      note = JrcNico::DomainAccess.authorize_resource!(@context.access, 'JrcServiceDesk::TicketNote', note_id)
      note.ticket_id == @ticket.id && note.idempotency_key == "nico_#{approval.command.id}_#{approval.command.request_id}"
    end
  end
end

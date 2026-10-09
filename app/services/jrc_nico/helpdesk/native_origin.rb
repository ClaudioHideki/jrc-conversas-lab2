# frozen_string_literal: true

# Reads native append-only evidence; a prefix/boolean alone never establishes origin.
class JrcNico::Helpdesk::NativeOrigin
  def initialize(record)
    @record = record
    @actor = actor
  end

  def classification
    value = origin
    return 'unknown' unless @actor && value['schema'] == 'native-operation-v1' && value['account_user_id'] == @actor.id
    return 'covered_human' if value['kind'] == 'operator'

    value['kind'] == 'operator_assisted_nico' && verified_command?(origin_command, value) ? 'human_approved_nico' : 'unknown'
  end

  def proven_nico?
    return classification == 'human_approved_nico' if origin.present?

    command = keyed_command
    command && verified_command?(command)
  end

  private

  def origin
    data = @record.is_a?(JrcServiceDesk::TicketEvent) ? @record.data : @record.try(:payload)
    data.is_a?(Hash) && data['origin'].is_a?(Hash) ? data['origin'] : {}
  end

  def actor
    membership = if @record.is_a?(JrcServiceDesk::TicketNote)
                   @record.author_membership
                 elsif @record.is_a?(JrcServiceDesk::TicketTask)
                   @record.created_by_membership
                 else
                   @record.actor_membership
                 end
    membership&.account_user if membership&.account_id == @record.account_id
  end

  def scoped_commands
    return JrcNico::Command.none unless @actor

    JrcNico::Command.joins(:session).where(status: 'succeeded', jrc_nico_sessions: { account_id: @record.account_id, user_id: @actor.user_id })
                    .where("jrc_nico_commands.arguments ->> 'ticket_id' = ?", @record.ticket_id.to_s)
  end

  def origin_command
    scoped_commands.find_by(id: origin['command_id'], session_id: origin['session_id'], request_id: origin['request_id'], tool: origin['tool'])
  end

  def keyed_command
    key = @record.is_a?(JrcServiceDesk::LifecycleTransition) ? @record.request_key : @record.try(:idempotency_key)
    scoped_commands.detect { |command| key == "nico_#{command.id}_#{command.request_id}" }
  end

  def verified_command?(command, value = nil)
    return false unless command&.approved_at && operator_authority?(command)

    return false if value && value['input_digest'] != input_digest(command)

    native_result?(command)
  end

  def operator_authority?(command)
    authority = command.execution_context.fetch('authorization', {})
    return false unless authority['source'] == 'operator' && authority['user_id'] == @actor.user_id
    return false if authority['mode'] == 'explicit_request' && authority['request_id'] != command.request_id

    true
  end

  def input_digest(command)
    values = command.arguments.slice('ticket_id', *input_fields(command))
    values['expected_lock_version'] = command.arguments['expected_lock_version']
    JrcServiceDesk::CanonicalJson.digest(values)
  end

  def input_fields(command)
    return JrcServiceDesk::UpdateTicketService::FIELDS + ['company_id'] if command.tool == 'update_service_ticket'

    JrcServiceDesk::LifecycleTransitionService::FIELDS
  end

  def native_result?(command)
    result = command.result
    return false unless result.is_a?(Hash)

    if @record.is_a?(JrcServiceDesk::TicketEvent)
      ticket_result?(command, result)
    elsif @record.is_a?(JrcServiceDesk::LifecycleTransition)
      command.tool == 'transition_service_ticket' && Array(result['resources']).include?([@record.class.name, @record.id])
    else
      interaction_result?(command, result)
    end
  end

  def ticket_result?(command, result)
    command.tool == 'update_service_ticket' && result['resource_type'] == 'JrcServiceDesk::Ticket' && result.dig('record', 'id') == @record.ticket_id
  end

  def interaction_result?(command, result)
    expected = @record.is_a?(JrcServiceDesk::TicketNote) ? 'add_service_ticket_note' : 'create_service_ticket_task'
    command.tool == expected && result['resource_type'] == @record.class.name && result.dig('record', 'id') == @record.id
  end
end

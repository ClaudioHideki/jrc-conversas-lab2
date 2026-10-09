# frozen_string_literal: true

# A reviewed draft only: no steps, approval, launch, recipients or provider dispatch.
class JrcNico::Helpdesk::GroupNativeCampaign
  TOOL = 'prepare_incident_campaign'.freeze

  def initialize(context:, event:, group_key:, input:)
    @context, @event, @group, @input = context, event, group_key, input
  end

  def evidence!(value)
    return unless @input

    arguments = arguments_for
    value[:resources].concat(cohort.resources + [['Inbox', inbox.id]])
    value[:evidence] << { kind: 'native_incident_campaign_draft', id: cohort.incident.id,
      source_digest: arguments.fetch('source_digest'), contact_ids: cohort.contacts.map(&:id), ticket_ids: cohort.tickets.map(&:id),
      inbox_id: inbox.id, automatic_execution: false }
  end

  def candidate
    { tool: TOOL, arguments: arguments_for } if @input
  end

  def source
    cohort.source.merge('event_id' => @event.id, 'unit_id' => cohort.incident.unit_id, 'inbox_id' => inbox.id)
  end

  def cohort
    @cohort ||= JrcNico::Helpdesk::GroupCampaignCohort.new(@context, @event, @input.fetch('incident_id'))
  end

  def inbox
    @inbox ||= @context.account.inboxes.find(@input.fetch('inbox_id')).tap do |row|
      unless row.channel_type == 'Channel::Whatsapp' && row.channel && @context.access.inbox_visible?(row)
        raise Pundit::NotAuthorizedError
      end
    end
  end

  private

  def arguments_for
    raise Pundit::NotAuthorizedError unless @group == 'C1' && @event.rule_key == 'R04' && @context.access.campaigns?

    @context.administrator!
    %w[incident_id inbox_id].each do |key|
      raise ArgumentError, 'Explicit positive native identifier required' unless @input[key].is_a?(Integer) && @input[key].positive?
    end
    name = @input['name']
    raise ArgumentError, 'Explicit reviewed draft name required' unless name.is_a?(String) && name.strip.size.between?(1, 200)

    arguments = @input.merge('event_id' => @event.id, 'source_digest' => JrcNico::Helpdesk::Definition.digest(source))
    JrcNico::ToolCatalog.new(@context.access).validate!(TOOL, arguments)
    arguments
  end
end

# frozen_string_literal: true

# Small current-ACL choices, never an account-wide customer export or an inferred recipient.
class JrcNico::Helpdesk::GroupDraftChoices
  def initialize(context, event, group, evidence)
    @context, @event, @group, @evidence = context, event, group, evidence
  end

  def call
    return {} unless @context.native.administrator?

    value = {}
    value[:knowledge] = { closed_cases: closed_cases } if @group == 'E'
    if @group == 'C1' && @event.rule_key == 'R04' && @context.access.campaigns?
      value[:campaign] = { incidents: incidents, inboxes: inboxes }
    end
    value
  end

  private

  def closed_cases
    @evidence.select { |row| row[:kind] == 'native_closed_solution' }.map do |row|
      { id: row.fetch(:id), ticket_id: row.fetch(:ticket_id), title: row.fetch(:title) }
    end
  end

  def incidents
    ids = @context.tickets.where(id: @event.evidence.fetch('ticket_ids')).where.not(incident_id: nil).pluck(:incident_id).uniq
    ids.filter_map do |id|
      source = JrcNico::Helpdesk::GroupCampaignCohort.new(@context, @event, id)
      { id: source.incident.id, title: source.incident.title, ticket_ids: source.tickets.map(&:id) }
    rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
      nil
    end
  end

  def inboxes
    @context.account.inboxes.where(channel_type: 'Channel::Whatsapp').order(:id).limit(200).filter_map do |inbox|
      { id: inbox.id, name: inbox.name } if inbox.channel && @context.access.inbox_visible?(inbox)
    end
  end
end

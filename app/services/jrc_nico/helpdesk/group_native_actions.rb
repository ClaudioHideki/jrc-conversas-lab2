# frozen_string_literal: true

# Existing CRM and conversation commands only, bound to the original native HelpDesk event.
class JrcNico::Helpdesk::GroupNativeActions
  CRM_TYPES = { 'JrcCrm::Lead' => JrcCrm::Lead, 'JrcCrm::Deal' => JrcCrm::Deal, 'JrcCrm::Activity' => JrcCrm::Activity }.freeze
  ACTIVITY_FIELDS = %w[title due_at lead_id deal_id description].freeze
  REPLY_FIELDS = %w[conversation_id content].freeze
  INPUT_FIELDS = { 'activity' => ACTIVITY_FIELDS, 'reply' => REPLY_FIELDS,
    'campaign' => %w[incident_id inbox_id name], 'knowledge' => %w[closed_transition_id title body generalization_reviewed] }.freeze

  def self.input(key, value)
    JrcServiceDesk::Input.attributes(value, INPUT_FIELDS.fetch(key))
  end

  def self.authorize_resource!(context, type, id)
    if type == 'Inbox'
      row = context.account.inboxes.find(id)
      raise Pundit::NotAuthorizedError unless context.access.inbox_visible?(row) && row.channel_type == 'Channel::Whatsapp' && row.channel

      return row
    end
    return JrcNico::DomainAccess.authorize_resource!(context.access, type, id) unless CRM_TYPES.key?(type)

    owner = type == 'JrcCrm::Activity' ? :user_id : :owner_id
    context.access.crm_scope(CRM_TYPES.fetch(type), owner: owner).find(id)
  end

  def self.authorize_result!(context, approval)
    command = approval.command
    return unless command.status == 'succeeded'
    if JrcNico::Helpdesk::GroupDraftActions::TOOLS.key?(command.tool)
      return JrcNico::Helpdesk::GroupDraftActions.new(context.access, command).authorize_result!
    end
    return authorize_activity_result!(context, command) if command.tool == 'create_activity'

    authorize_reply_result!(context, command) if command.tool == 'send_message'
  end

  def self.authorize_activity_result!(context, command)
    JrcNico::Helpdesk::GroupNativeActivity.authorize_result!(context, command)
  end

  def self.authorize_reply_result!(context, command)
    JrcNico::Helpdesk::GroupNativeReply.authorize_result!(context, command)
  end

  private_class_method :authorize_activity_result!, :authorize_reply_result!

  def initialize(context:, event:, group_key:, input:)
    @activity = JrcNico::Helpdesk::GroupNativeActivity.new(context: context, event: event, group_key: group_key, input: input['activity'])
    @reply = JrcNico::Helpdesk::GroupNativeReply.new(context: context, event: event, group_key: group_key, input: input['reply'])
    @campaign = JrcNico::Helpdesk::GroupNativeCampaign.new(context: context, event: event, group_key: group_key, input: input['campaign'])
    @knowledge = JrcNico::Helpdesk::GroupNativeKnowledge.new(context: context, event: event, group_key: group_key, input: input['knowledge'])
  end

  def evidence!(value)
    @activity.evidence!(value)
    @reply.evidence!(value)
    @campaign.evidence!(value)
    @knowledge.evidence!(value)
  end

  def candidates
    [@activity.candidate, @reply.candidate, @campaign.candidate, @knowledge.candidate].compact
  end
end

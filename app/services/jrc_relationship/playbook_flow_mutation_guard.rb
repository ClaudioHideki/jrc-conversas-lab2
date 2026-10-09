# frozen_string_literal: true

class JrcRelationship::PlaybookFlowMutationGuard
  def initialize(reference)
    @reference = reference
    @context = reference.context
    @conversation = reference.conversation
  end

  def authorize!(type, data)
    raise ArgumentError, 'playbook_flow_effect_not_approved' unless @reference.policy.effect_allowed?(type)
    raise Pundit::NotAuthorizedError unless ConversationPolicy.new(@context.to_h, @conversation).show?

    authorize_native_mutation!(type, data)
    true
  end

  def native_lead
    scope = @context.account.jrc_crm_leads.lock('FOR SHARE')
    row = scope.find_by(idempotency_key: "conversation:#{@conversation.id}") || scope.find_by(conversation_id: @conversation.id)
    return unless row

    valid = row.conversation_id == @conversation.id && row.contact_id == @reference.contact.id &&
            row.business_unit_id == @reference.assignment.business_unit_id && JrcCrm::LeadPolicy.new(@context.to_h, row).show?
    raise Pundit::NotAuthorizedError unless valid

    row
  end

  def native_deal(data)
    raise Pundit::NotAuthorizedError unless JrcOperations::Access.crm?(@context.member)
    raise ArgumentError, 'playbook_flow_deal_fields_invalid' unless data.keys.sort == %w[deal_id stage_id]

    deal = JrcCrm::Deal.where(account_id: @context.account.id).lock.find(explicit_id(data.fetch('deal_id')))
    lead = native_lead
    valid = lead && deal.lead_id == lead.id && deal.contact_id == @reference.contact.id &&
            deal.company_id == @reference.contact.company_id && deal.deal_conversations.where(account_id: @context.account.id,
                                                                                             conversation_id: @conversation.id).lock.exists? &&
            JrcCrm::DealPolicy.new(@context.to_h, deal).show? && JrcCrm::DealPolicy.new(@context.to_h, deal).move_stage?
    raise Pundit::NotAuthorizedError unless valid

    JrcCrm::Pipeline.where(account_id: @context.account.id, active: true).lock('FOR SHARE').find(deal.pipeline_id)
    stage = JrcCrm::Stage.where(account_id: @context.account.id, pipeline_id: deal.pipeline_id, active: true)
                         .lock('FOR SHARE').find(explicit_id(data.fetch('stage_id')))
    raise ArgumentError, 'playbook_flow_deal_closed' unless deal.open?
    raise ArgumentError, 'playbook_flow_lost_reason_required' if stage.is_lost? && deal.lost_reason_id.blank?

    [deal, stage]
  end

  private

  def authorize_native_mutation!(type, data)
    case type
    when 'contact' then authorize_contact!(data)
    when 'labels' then authorize_labels!(data)
    when 'assign' then authorize_assignment!(data)
    when 'create_lead', 'activity' then authorize_crm!(type, data)
    when 'move_deal' then native_deal(data)
    when 'nico' then authorize_delegation!(data)
    when 'status' then raise ArgumentError unless %w[open pending resolved].include?(data['status'])
    else raise ArgumentError, 'playbook_flow_native_mutation_unsupported'
    end
  end

  def authorize_contact!(data)
    raise ArgumentError unless %w[name email phone_number].include?(data.fetch('field'))
    raise Pundit::NotAuthorizedError unless ContactPolicy.new(@context.to_h, @reference.contact).update?
  end

  def authorize_labels!(data)
    labels = data.fetch('labels')
    raise ArgumentError unless labels.is_a?(Array) && labels.uniq == labels && %w[add remove].include?(data.fetch('operation'))
    raise Pundit::NotAuthorizedError unless @context.account.labels.where(title: labels).count == labels.size
  end

  def authorize_assignment!(data)
    raise ArgumentError, 'Explicit native assignment required' if data.values_at('team_id', 'agent_id').all?(&:blank?)

    @context.account.teams.lock('FOR SHARE').find(explicit_id(data['team_id'])) if data['team_id'].present?
    authorize_agent!(data['agent_id']) if data['agent_id'].present?
  end

  def authorize_agent!(id)
    member = @context.account.account_users.lock('FOR SHARE').find_by!(user_id: explicit_id(id))
    InboxMember.where(inbox_id: @conversation.inbox_id, user_id: member.user_id).lock('FOR SHARE').load
    valid = @conversation.inbox.members.exists?(member.user_id) || member.administrator?
    raise Pundit::NotAuthorizedError unless valid
  end

  def authorize_crm!(type, data)
    raise Pundit::NotAuthorizedError unless JrcOperations::Access.crm?(@context.member)
    raise Pundit::NotAuthorizedError unless JrcCrm::LeadPolicy.new(@context.to_h, JrcCrm::Lead.new(account: @context.account)).create?

    unit_id = @reference.assignment.business_unit_id
    JrcCrm::BusinessUnit.active.where(account_id: @context.account.id).find(unit_id) if unit_id
    native_lead
    @context.account.account_users.lock('FOR SHARE').find_by!(user_id: explicit_id(data.fetch('user_id'))) if type == 'activity'
  end

  def explicit_id(value)
    id = if value.is_a?(Integer)
           value
         elsif value.is_a?(String) && value.match?(/\A[1-9]\d{0,18}\z/)
           value.to_i
         end
    return id if id && id.between?(1, 9_223_372_036_854_775_807)

    raise ArgumentError, 'Explicit native action target required'
  end

  def authorize_delegation!(data)
    raise ArgumentError, 'playbook_flow_delegation_fields_invalid' unless (data.keys - %w[objective hours allowed_actions]).empty?
    objective = JrcFlows::Evaluator.new(@reference.native_variables).render(data.fetch('objective'))
    raise ArgumentError, 'playbook_flow_delegation_objective_invalid' unless objective.is_a?(String) && objective.bytesize.between?(1, 2000)
    raise ArgumentError, 'playbook_flow_delegation_hours_invalid' unless data.fetch('hours', 2).is_a?(Integer) && (1..8).cover?(data.fetch('hours', 2))

    actions = data.fetch('allowed_actions')
    valid = actions.is_a?(Array) && actions.uniq == actions && (actions - JrcNico::DelegatedActions::GROUPS.keys).empty?
    raise ArgumentError, 'playbook_flow_delegation_actions_invalid' unless valid

    access = JrcNico::OperationalAccess.new(account: @context.account, user: @context.user).authorize!
    access.conversation(@conversation.display_id)
    raise Pundit::NotAuthorizedError if (actions & %w[leads proposals meetings]).any? && !access.crm?
    enabled = @context.account.custom_attributes['nico_customer_delegation_enabled'] == true && ENV['NICO_MODE'] == 'provider'
    raise ArgumentError, 'playbook_flow_delegation_disabled' unless enabled

    provider = JrcAi::AccountProvider.resolve(@context.account)
    JrcAi::Provider.where(account_id: @context.account.id).lock('FOR SHARE').find(provider.id)
    raise Pundit::NotAuthorizedError if @conversation.assignee_agent_bot_id || JrcFlows::Access.inbox_bot_owned?(@conversation)
    raise Pundit::NotAuthorizedError if JrcNico::Delegation.active.where(account_id: @context.account.id, conversation_id: @conversation.id).exists?
  rescue JrcNico::RuntimeClient::Error
    raise ArgumentError, 'playbook_flow_account_provider_unavailable'
  end
end

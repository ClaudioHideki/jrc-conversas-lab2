# frozen_string_literal: true

# Only the approved mutable identity fields are journalled. Native message
# activity timestamps may change during a legitimate input wait.
class JrcRelationship::PlaybookFlowMutationState
  CONTACT_FIELDS = %w[id account_id company_id name email phone_number].freeze
  CONVERSATION_FIELDS = %w[id account_id contact_id contact_inbox_id inbox_id assignee_id assignee_agent_bot_id team_id status].freeze
  RESOURCE_FIELDS = {
    'lead' => %w[id account_id company_id business_unit_id contact_id conversation_id owner_id team_id name email phone
                 source status idempotency_key classified_at company_name converted_at custom_attributes notes score temperature
                 created_at updated_at],
    'activity' => %w[id account_id company_id business_unit_id contact_id conversation_id lead_id deal_id user_id title description
                     activity_type status due_at completed_at metadata organization_id legacy_sales_activity_id created_at updated_at],
    'deal' => %w[id account_id contact_id company_id lead_id pipeline_id stage_id owner_id team_id status probability
                 value_cents title lost_reason_id lost_reason_note won_at lost_at lock_version updated_at],
    'delegation' => %w[id account_id conversation_id user_id agent_bot_id objective allowed_actions allow_crm status version expires_at]
  }.freeze
  RESOURCE_MODELS = { 'lead' => JrcCrm::Lead, 'activity' => JrcCrm::Activity,
                      'deal' => JrcCrm::Deal, 'delegation' => JrcNico::Delegation }.freeze

  def initialize(run)
    @run = run
  end

  def call(resources = [])
    conversation = Conversation.where(account_id: @run.account_id).find(@run.conversation_id)
    contact = Contact.where(account_id: @run.account_id).find(conversation.contact_id)
    { 'contact' => contact.attributes.slice(*CONTACT_FIELDS),
      'conversation' => conversation.attributes.slice(*CONVERSATION_FIELDS),
      'labels' => labels(conversation), 'resources' => resources.map { |record| resource(record.fetch('kind'), record.fetch('id')) } }
  end

  def resource(kind, id)
    row = RESOURCE_MODELS.fetch(kind).where(account_id: @run.account_id).lock('FOR SHARE').find(id)
    valid = case kind
            when 'deal'
              row.contact_id == @run.conversation.contact_id && row.deal_conversations.exists?(account_id: @run.account_id,
                                                                                              conversation_id: @run.conversation_id)
            when 'delegation' then row.conversation_id == @run.conversation_id
            else row.conversation_id == @run.conversation_id && row.contact_id == @run.conversation.contact_id
            end
    raise Pundit::NotAuthorizedError unless valid

    { 'kind' => kind, 'id' => row.id, 'attributes' => row.attributes.slice(*RESOURCE_FIELDS.fetch(kind)).as_json }
  end

  def variable_resources(type)
    if type == 'move_deal'
      deal = resource('deal', @run.variables.fetch('deal_id'))
      return [deal, resource('lead', deal.fetch('attributes').fetch('lead_id'))]
    end
    return [resource('delegation', @run.variables.fetch('delegation_id'))] if type == 'nico'

    outputs = { 'lead' => @run.variables['lead_id'], 'activity' => @run.variables['activity_id'] }
    outputs = outputs.slice('lead') if type == 'create_lead'
    outputs = {} unless %w[create_lead activity].include?(type)
    outputs.filter_map do |kind, id|
      resource(kind, id) if id
    end
  end

  def target_before(type, data)
    type == 'move_deal' ? resource('deal', data.fetch('deal_id')) : nil
  end

  private

  def labels(conversation)
    titles = conversation.label_list.sort
    records = @run.account.labels.where(title: titles).order(:id).pluck(:id, :title)
    raise ArgumentError, 'playbook_flow_native_labels_changed' unless records.map(&:last).sort == titles

    records
  end
end

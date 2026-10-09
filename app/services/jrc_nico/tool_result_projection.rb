# Finite native tool DTOs; OperatorAccess policies continue to scope each conversation before projection.
class JrcNico::ToolResultProjection
  RECORD_FIELDS = %w[id name title status phone_number email contact_id lead_id deal_id due_at total_cents].freeze

  def initialize(access, account:)
    @access = access
    @account = account
  end

  def record_result(record, message, route)
    attributes = record.attributes
    { message: "#{message}: #{attributes['name'] || attributes['title']} (##{record.id})", resource_type: record.class.name,
      record: attributes.slice(*RECORD_FIELDS), route_name: route }
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
end

class JrcRelationship::CadencePlan
  def initialize(context)
    @context = context
  end

  def snapshot(inputs, lock: false)
    raise ArgumentError, 'Select exactly one customer and their conversation' unless inputs.fetch('ids').one?

    assignment = @context.assignment(inputs.fetch('ids').first, write: true)
    conversation = reviewed_conversation(inputs, assignment, lock)
    verify_conditions!(assignment, inputs.fetch('playbook_id'))

    { 'conversation_id' => conversation.id, 'conversation_number' => conversation.display_id, 'contact_name' => conversation.contact.name,
      'contact_id' => conversation.contact_id, 'inbox_id' => conversation.inbox_id,
      'control_revision' => conversation.jrc_effect_control_revision, 'status' => conversation.status,
      'message_watermark' => conversation.messages.maximum(:id).to_i }
  end

  private

  def reviewed_conversation(inputs, assignment, lock)
    conversation = Conversation.find_by!(account_id: @context.account.id, display_id: inputs.fetch('conversation_id'))
    conversation.lock! if lock
    raise Pundit::NotAuthorizedError unless ConversationPolicy.new(@context.to_h, conversation).show?
    raise ArgumentError, 'Conversation must belong to the selected customer' unless same_customer?(assignment, conversation.contact)

    conversation
  end

  def verify_conditions!(assignment, book_id)
    book = JrcRelationship::Playbook.find_by!(account_id: @context.account.id, id: book_id)
    signals = JrcRelationship::CustomerSignals.new(assignment: assignment, context: @context).call if book.conditions.present?
    return unless signals && !JrcRelationship::PlaybookConditions.match?(book.conditions, signals)

    raise ArgumentError, 'Selected customer does not match playbook conditions'
  end

  def same_customer?(assignment, contact)
    assignment.contact_id == contact.id || (assignment.company_id.present? && assignment.company_id == contact.company_id)
  end
end

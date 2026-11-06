# Finite native work only. No public messages, provider calls or second Flow engine.
class JrcRelationship::ReviewedCadence
  def initialize(context)
    @account_id = context.account.id
    @actor_id = context.user.id
    @authority = JrcRelationship::BatchReviewAuthority.new(account_id: @account_id, actor_id: @actor_id)
  end

  def self.enroll!(context:, assignment:, review:)
    frozen = source_snapshot(review, assignment)
    record = JrcRelationship::CadenceEnrollment.create!(account: context.account, actor_id: context.user.id,
                                                        assignment: assignment, batch_review: review,
                                                        conversation_id: frozen.fetch('conversation_id'), snapshot: frozen,
                                                        starts_at: Time.iso8601(review.inputs.fetch('starts_at')))
    frozen.fetch('book').fetch('steps').each_with_index do |step, ordinal|
      record.steps.create!(account: context.account, ordinal: ordinal, definition: step,
                           due_at: record.starts_at + step.fetch('after_days').days)
    end
    record
  end

  def self.source_snapshot(review, assignment)
    row = review.snapshot.fetch('rows').find { |item| item['assignment_id'] == assignment.id }
    review.snapshot.fetch('cadence').merge(
      'book' => review.snapshot.fetch('book'), 'access_signature' => review.snapshot.fetch('access_signature'),
      'assignment_digest' => row.fetch('digest')
    )
  end
  private_class_method :source_snapshot

  def get(id)
    transaction { |context| project(find(id, context)) }
  end

  def cancel(id)
    transaction do |context|
      record = find(id, context)
      stop!(record, 'CANCELED_BY_OPERATOR') if record.state == 'active'
      project(record)
    end
  end

  def advance(id)
    transaction do |context|
      record = find(id, context)
      if record.state == 'active'
        conversation = Conversation.where(account_id: @account_id).lock.find(record.conversation_id)
        raise Pundit::NotAuthorizedError unless ConversationPolicy.new(context.to_h, conversation).show?

        reason = stop_reason(record, conversation, context)
        reason ? stop!(record, reason) : apply_due(record, context)
      end
      project(record)
    end
  end

  # A supervisor may explicitly stop remaining work. This does not transfer
  # execution authority or expose the original actor's frozen source contents.
  def cancel_for_team(analyst_id:, id:, expected_revision:, reason:)
    transaction do |context|
      record, reviewed_analyst_id = find_for_team(id, analyst_id, context)
      explanation = team_stop_reason!(reason)
      raise ActiveRecord::StaleObjectError.new(record, 'cancel') unless record.revision == Integer(expected_revision.to_s, 10)
      raise ArgumentError, 'Cadence is not active' unless record.state == 'active'

      before = { state: record.state, revision: record.revision }
      stop!(record, 'CANCELED_BY_SUPERVISOR')
      context.audit!(record, before: before,
                             after: { state: record.state, revision: record.revision, reason: explanation, reviewed_analyst_id: reviewed_analyst_id },
                             action: 'cadence_stopped_by_team')
      { id: record.id, state: record.state, revision: record.revision, stop_reason: record.stop_reason }
    end
  end

  # Revoked authority can stop approved work, never execute native work.
  def self.stop_revoked(id)
    JrcRelationship::CadenceEnrollment.transaction do
      record = JrcRelationship::CadenceEnrollment.lock.find_by(id: id, state: 'active')
      next unless record

      record.steps.where(state: 'pending').find_each { |step| step.update!(state: 'canceled') }
      record.update!(state: 'stopped', stop_reason: 'AUTHORITY_REVOKED', revision: record.revision + 1)
    end
  end

  private

  def find_for_team(id, analyst_id, context)
    raise Pundit::NotAuthorizedError unless context.policy.team?

    analyst = context.account.users.find(analyst_id)
    source = JrcRelationship::AnalystCadences.responsibilities(context.account, analyst)
    record = source.lock.find(id)
    context.assignment(record.assignment_id, write: true).lock!
    raise ActiveRecord::StaleObjectError.new(record, 'cancel') unless source.exists?(id: record.id)

    [record, analyst.id]
  end

  def team_stop_reason!(reason)
    raise ArgumentError, 'A bounded reason is required to stop pending cadence work' unless
      reason.is_a?(String) && reason.strip.present? && reason.length <= 4000

    reason.strip
  end

  def transaction(&)
    JrcRelationship::CadenceEnrollment.transaction { @authority.call(&) }
  end

  def find(id, context)
    record = JrcRelationship::CadenceEnrollment.where(account_id: @account_id, actor_id: @actor_id).lock.find(id)
    context.assignment(record.assignment_id, write: true).lock!
    record
  end

  def stop_reason(record, conversation, context)
    source = record.snapshot
    return 'AUTHORITY_CHANGED' unless context.access_signature == source.fetch('access_signature')
    return 'CONTACT_REPLIED' if contact_replied?(conversation, source)

    assignment = context.assignment(record.assignment_id, write: true)
    digest = JrcRelationship::BatchReviewPlan.new(context).row_snapshot(assignment).fetch('digest')
    return 'CUSTOMER_CHANGED' unless digest == source.fetch('assignment_digest')
    return 'CONVERSATION_CHANGED' unless same_conversation?(conversation, source)
    return 'CONDITIONS_CHANGED' unless matches_conditions?(assignment, source, context)

    nil
  end

  def same_conversation?(conversation, source)
    conversation.contact_id == source.fetch('contact_id') && conversation.inbox_id == source.fetch('inbox_id') &&
      conversation.jrc_effect_control_revision == source.fetch('control_revision')
  end

  def matches_conditions?(assignment, source, context)
    conditions = source.fetch('book').fetch('conditions')
    return true if conditions.empty?

    signals = JrcRelationship::CustomerSignals.new(assignment: assignment, context: context).call
    JrcRelationship::PlaybookConditions.match?(conditions, signals)
  end

  def contact_replied?(conversation, source)
    incoming = conversation.messages.where('id > ?', source.fetch('message_watermark'))
    incoming = incoming.where(message_type: :incoming, private: false, sender_type: 'Contact', sender_id: source.fetch('contact_id'))
    incoming = incoming.where("source_id IS NULL OR source_id NOT LIKE 'jrc-history:%'")
    incoming.exists?
  end

  def apply_due(record, context)
    step = record.steps.where(state: 'pending').order(:due_at, :ordinal).lock.first
    return unless step && step.due_at <= Time.current

    receipt = JrcRelationship::CadenceActionBudget.new(context, record, step).call do
      JrcRelationship::Playbooks.new(context).apply_scheduled_step!(
        assignment: context.assignment(record.assignment_id, write: true), step: step.definition,
        key: "cadence:#{record.id}:#{step.ordinal}", starts_at: record.starts_at
      )
    end
    return unless receipt

    step.update!(state: 'applied', receipt: receipt)
    record.update!(state: record.steps.exists?(state: 'pending') ? 'active' : 'completed', revision: record.revision + 1)
  end

  def stop!(record, reason)
    record.steps.where(state: 'pending').find_each { |step| step.update!(state: 'canceled') }
    record.update!(state: 'stopped', stop_reason: reason, revision: record.revision + 1)
  end

  def project(record)
    { 'id' => record.id, 'state' => record.state, 'revision' => record.revision, 'stop_reason' => record.stop_reason,
      'assignment_id' => record.assignment_id, 'conversation_id' => record.conversation_id,
      'book_name' => record.snapshot.dig('book', 'name'), 'book_version' => record.snapshot.dig('book', 'version'),
      'steps' => record.steps.order(:ordinal).map do |step|
        { 'ordinal' => step.ordinal, 'title' => step.definition.fetch('title'), 'due_at' => step.due_at.iso8601(6),
          'state' => step.state, 'receipt' => step.receipt }
      end }.merge(JrcRelationship::CadenceActionBudget.deferral(record))
  end
end

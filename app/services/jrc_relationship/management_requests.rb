# Records intent only. Routing points to an existing native reviewed batch or
# an already audited withdrawal/restoration; never manufactures an approval.
class JrcRelationship::ManagementRequests
  def initialize(context)
    @member = context.member
  end

  def create!(kind:, reason:, idempotency_key:, assignment_id: nil, analyst_id: nil)
    raise ArgumentError, 'Select a request kind' unless %w[transfer suspend restore].include?(kind)
    raise ArgumentError, 'Provide a reason' unless reason.is_a?(String) && reason.strip.length.between?(1, 2000)
    raise ArgumentError, 'Invalid request key' unless idempotency_key.is_a?(String) && idempotency_key.match?(/\A[a-zA-Z0-9:_-]{1,120}\z/)
    JrcRelationship::ManagementRequest.transaction do
      with_authority do |context|
        if kind == 'transfer'
          raise ArgumentError, 'Transfer requires only a customer' if analyst_id || !positive_id?(assignment_id)
          source = context.assignment(assignment_id)
          raise Pundit::NotAuthorizedError unless context.policy.manage? &&
            JrcRelationship::LocalAccess.assignment_allowed?(context.member, source, 'request_transfer')
        else
          raise ArgumentError, 'Eligibility request requires only an analyst' if assignment_id || !positive_id?(analyst_id)
          raise Pundit::NotAuthorizedError unless context.policy.team? && context.policy.local?('request_eligibility')
          source = context.assignable_users.find(analyst_id)
        end
        input = { kind: kind, assignment_id: kind == 'transfer' ? source.id : nil, analyst_id: kind == 'transfer' ? nil : source.id, reason: reason.strip }
        digest = JrcApprovals::Ledger.digest(input)
        JrcApprovals::Ledger.lock!(context.account.id, "relationship_request:#{context.user.id}:#{idempotency_key}")
        row = JrcRelationship::ManagementRequest.find_by(account_id: context.account.id, requester_id: context.user.id, idempotency_key: idempotency_key)
        if row
          raise ArgumentError, 'Request key belongs to another intent' unless row.input_digest == digest
          next present(row, context: context)
        end
        row = JrcRelationship::ManagementRequest.create!(**input, account: context.account, requester: context.user,
          idempotency_key: idempotency_key, input_digest: digest)
        context.audit!(row, action: 'management_requested', after: { kind: kind, reason: reason.strip, assignment_id: row.assignment_id, analyst_id: row.analyst_id })
        present(row, context: context)
      end
    end
  end

  def index(page: 1)
    context = JrcRelationship::Context.new(@member)
    signature = context.access_signature
    rows = visible(context)
    number = Integer(page.to_s, 10).clamp(1, 10000)
    result = { payload: rows.order(id: :desc).limit(25).offset((number - 1) * 25).map { |row| present(row, context: context) },
      meta: { page: number, per_page: 25, total: rows.count, can_route: context.policy.team? && context.policy.manage? } }
    fresh = JrcRelationship::Context.new(@member)
    raise Pundit::NotAuthorizedError unless fresh.access_signature == signature && fresh.user.reload.active_for_authentication?
    result
  end

  def resolution_options(id:, page: 1)
    context = JrcRelationship::Context.new(@member)
    signature = context.access_signature
    raise Pundit::NotAuthorizedError unless context.policy.team? && context.policy.manage?
    row = visible(context).find(id)
    raise ArgumentError, 'Only pending requests accept a routing receipt' unless row.state == 'pending'
    size, number = 25, Integer(page.to_s, 10).clamp(1, 10000)
    if row.kind == 'transfer'
      context.assignment(row.assignment_id)
      rows = JrcRelationship::BatchReview.where(account_id: context.account.id, actor_id: context.user.id, state: %w[previewed running completed])
        .where("inputs ->> 'operation' = 'assign' AND inputs -> 'ids' @> ?::jsonb", [row.assignment_id].to_json)
      options = rows.order(id: :desc).limit(size).offset((number - 1) * size).map { |r| { id: r.id, state: r.state, created_at: r.created_at } }
    else
      raise Pundit::NotAuthorizedError unless context.policy.configure? && context.policy.local?('manage_eligibility')
      analyst = context.assignable_users.find(row.analyst_id)
      member = context.account.account_users.find_by!(user_id: analyst.id)
      action = row.kind == 'suspend' ? 'analyst_withdrawn' : 'analyst_withdrawal_reversed'
      rows = JrcCrm::AuditEvent.where(account_id: context.account.id, resource_type: 'AccountUser', resource_id: member.id,
        actor_type: 'User', actor_id: context.user.id).where('created_at >= ?', row.created_at)
        .where("metadata ->> 'action' = ? AND to_value ->> 'eligibility_version' = ?", action, member.jrc_relationship_eligibility_version.to_s)
      options = rows.order(id: :desc).limit(size).offset((number - 1) * size).map { |r| { id: r.id, state: action, created_at: r.created_at } }
    end
    fresh = JrcRelationship::Context.new(@member)
    raise Pundit::NotAuthorizedError unless fresh.access_signature == signature && fresh.user.reload.active_for_authentication?
    { payload: options, meta: { page: number, per_page: size, total: rows.count } }
  end

  def route!(id:, expected_version:, batch_review_id: nil, resolution_event_id: nil)
    raise ArgumentError, 'Use an explicit revision' unless expected_version.is_a?(Integer) && expected_version >= 0
    JrcRelationship::ManagementRequest.transaction do
      with_authority do |context|
        raise Pundit::NotAuthorizedError unless context.policy.team? && context.policy.manage?
        row = visible(context).lock.find(id)
        raise ActiveRecord::StaleObjectError.new(row, 'route') unless row.lock_version == expected_version
        raise ArgumentError, 'Request already routed' unless row.state == 'pending'
        if row.kind == 'transfer'
          raise ArgumentError, 'Select a native reviewed batch only' unless positive_id?(batch_review_id) && resolution_event_id.nil?
          review = JrcRelationship::BatchReview.where(account_id: context.account.id, actor_id: context.user.id).find(batch_review_id)
          raise ArgumentError, 'Batch does not contain the requested transfer' unless review.inputs['operation'] == 'assign' &&
            review.inputs.fetch('ids').include?(row.assignment_id) && %w[previewed running completed].include?(review.state)
          JrcRelationship::LocalAccess.authorize_assignment!(context, context.assignment(row.assignment_id), 'execute_transfer')
          row.batch_review = review
        else
          raise ArgumentError, 'Select an actual native eligibility receipt only' unless positive_id?(resolution_event_id) && batch_review_id.nil?
          raise Pundit::NotAuthorizedError unless context.policy.configure? && context.policy.local?('manage_eligibility')
          analyst = context.assignable_users.find(row.analyst_id)
          member = context.account.account_users.find_by!(user_id: analyst.id)
          event = JrcCrm::AuditEvent.where(account_id: context.account.id, resource_type: 'AccountUser', resource_id: member.id,
            actor_type: 'User', actor_id: context.user.id).find(resolution_event_id)
          action = row.kind == 'suspend' ? 'analyst_withdrawn' : 'analyst_withdrawal_reversed'
          raise ArgumentError, 'Receipt does not prove this eligibility operation' unless event.metadata['action'] == action && event.created_at >= row.created_at &&
            event.to_value['eligibility_version'] == member.jrc_relationship_eligibility_version
          row.resolution_event = event
        end
        row.state = 'routed'
        row.save!
        context.audit!(row, action: 'management_request_routed', after: { kind: row.kind, batch_review_id: row.batch_review_id, resolution_event_id: row.resolution_event_id })
        present(row, context: context)
      end
    end
  end

  private

  def with_authority(&block)
    JrcRelationship::BatchReviewAuthority.new(account_id: @member.account_id, actor_id: @member.user_id, write: false).call(&block)
  end

  def positive_id?(value)
    value.is_a?(Integer) && value.positive?
  end

  def visible(context)
    base = JrcRelationship::ManagementRequest.where(account_id: context.account.id)
    return base.where(requester_id: context.user.id) unless context.policy.team?
    assignments = context.assignments.select(:id)
    analysts = context.assignable_users.select(:id)
    base.where(assignment_id: assignments).or(base.where(analyst_id: analysts)).or(base.where(requester_id: context.user.id))
  end

  def present(row, context:)
    # Receipt contains no copied customer names, contacts, documents or source data.
    visible_source = row.assignment_id ? context.assignments.exists?(id: row.assignment_id) : context.assignable_users.exists?(id: row.analyst_id)
    return row.attributes.slice('id', 'kind', 'state', 'requester_id', 'lock_version', 'created_at').merge('redacted' => true) unless visible_source
    row.attributes.slice('id', 'kind', 'state', 'reason', 'assignment_id', 'analyst_id', 'requester_id',
      'batch_review_id', 'resolution_event_id', 'lock_version', 'created_at')
  end
end

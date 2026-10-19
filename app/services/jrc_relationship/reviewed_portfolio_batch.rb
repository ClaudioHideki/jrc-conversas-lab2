class JrcRelationship::ReviewedPortfolioBatch
  def initialize(context)
    @account_id = context.account.id
    @actor_id = context.user.id
    @authority = JrcRelationship::BatchReviewAuthority.new(account_id: @account_id, actor_id: @actor_id)
  end

  def preview(raw)
    transaction do |context|
      plan = JrcRelationship::BatchReviewPlan.new(context)
      inputs = plan.normalize(raw)
      lock_request(inputs.fetch('request_id'))
      previous = reviews.find_by(request_id: inputs.fetch('request_id'))
      if previous
        raise ArgumentError, 'Review request conflict' unless previous.inputs == inputs

        next project(previous, context)
      end
      snapshot = plan.snapshot(inputs, lock: true)
      review = reviews.create!(inputs: inputs, snapshot: snapshot, digest: plan.digest([inputs, snapshot]),
                               request_id: inputs.fetch('request_id'), expires_at: 15.minutes.from_now)
      snapshot.fetch('rows').each_with_index do |row, ordinal|
        review.items.create!(account_id: @account_id, assignment_id: row.fetch('assignment_id'), ordinal: ordinal)
      end
      project(review, context)
    end
  end

  def get(id)
    transaction { |context| project(reviews.find(id), context) }
  end

  def approve(id, digest:)
    transaction do |context|
      review = reviews.lock.find(id)
      raise ArgumentError, 'Review identity mismatch' unless review.digest == digest
      next project(review, context) if %w[running completed].include?(review.state)
      raise ArgumentError, 'Review is not available' unless review.state == 'previewed'
      raise ArgumentError, 'Review expired' if review.expires_at <= Time.current

      JrcRelationship::BatchReviewPlan.new(context).validate!(review)
      review.update!(state: 'running', revision: review.revision + 1)
      project(review, context)
    end
  end

  def cancel(id)
    transaction do |context|
      review = reviews.lock.find(id)
      if %w[previewed running].include?(review.state)
        review.items.where(state: 'pending').find_each { |item| item.update!(state: 'canceled') }
        review.update!(state: 'canceled', revision: review.revision + 1)
      end
      project(review, context)
    end
  end

  def advance(id, limit: 5)
    raise ArgumentError, 'Invalid batch budget' unless limit.is_a?(Integer) && limit.between?(1, 10)

    limit.times { break unless apply_next(id) }
    get(id)
  end

  private

  def lock_request(request_id)
    key = "reviewed-batch:#{@account_id}:#{@actor_id}:#{request_id}"
    connection = ActiveRecord::Base.connection
    connection.execute("SELECT pg_advisory_xact_lock(hashtextextended(#{connection.quote(key)}, 0))")
  end

  def reviews
    JrcRelationship::BatchReview.where(account_id: @account_id, actor_id: @actor_id)
  end

  def transaction(&)
    JrcRelationship::BatchReview.transaction { @authority.call(&) }
  end

  def apply_next(id)
    item_id = nil
    transaction do |context|
      review = reviews.lock.find(id)
      next false unless review.state == 'running'

      item = review.items.where(state: 'pending').order(:ordinal).lock.first
      next false unless item

      item_id = item.id
      receipt = perform_item(review, item, context)
      commit_receipt(review, item, receipt)
      true
    end
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound, ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout
    raise
  rescue StandardError => e
    raise unless item_id

    Rails.logger.warn({ event: 'reviewed_batch_item_failed', batch_id: id, item_id: item_id, error_class: e.class.name }.to_json)
    record_failure(id, item_id)
    false
  end

  def perform_item(review, item, context)
    assignment = context.assignment(item.assignment_id, write: true)
    assignment.lock!
    JrcRelationship::BatchReviewPlan.new(context).validate!(review, assignment: assignment)
    receipt = apply_reviewed_item(review, item, assignment, context)
    current = JrcRelationship::Context.new(context.member.reload)
    raise Pundit::NotAuthorizedError unless current.policy.manage? && current.access_signature == review.snapshot.fetch('access_signature')

    receipt
  end

  def apply_reviewed_item(review, item, assignment, context)
    if review.inputs['operation'] == 'cadence'
      enrollment = JrcRelationship::ReviewedCadence.enroll!(context: context, assignment: assignment, review: review)
      { 'updated' => 1, 'operation' => 'cadence', 'assignment_id' => assignment.id, 'cadence_id' => enrollment.id }
    else
      apply_native(review, item, context)
      JrcRelationship::BatchNativeReceipt.new(context, review, item).call
    end
  end

  def commit_receipt(review, item, receipt)
    item.update!(state: 'applied', receipt: receipt)
    state = review.items.exists?(state: 'pending') ? 'running' : 'completed'
    review.update!(state: state, revision: review.revision + 1)
  end

  def record_failure(id, item_id)
    JrcRelationship::BatchReview.transaction do
      review = reviews.lock.find(id)
      next unless review.state == 'running'

      review.items.where(id: item_id, state: 'pending').find_each do |item|
        item.update!(state: 'failed', error_code: 'BATCH_NATIVE_OPERATION_FAILED')
      end
      review.items.where(state: 'pending').find_each { |item| item.update!(state: 'canceled') }
      review.update!(state: 'attention', revision: review.revision + 1)
    end
  end

  def apply_native(review, item, context)
    inputs = review.inputs.merge('ids' => [item.assignment_id], 'request_id' => "reviewed:#{review.id}:#{item.id}")
    count = JrcRelationship::PortfolioBatch.new(context, ActionController::Parameters.new(inputs)).call
    raise ArgumentError, 'Native item result mismatch' unless count == 1
  end

  def project(review, context)
    review.inputs.fetch('ids').each { |id| context.assignment(id) }
    { 'id' => review.id, 'state' => review.state, 'revision' => review.revision, 'digest' => review.digest,
      'expires_at' => review.expires_at.iso8601(6), 'inputs' => review.inputs,
      'summary' => review.snapshot['summary'],
      'items' => review.items.order(:ordinal).map do |item|
        row = review.snapshot.fetch('rows').fetch(item.ordinal)
        { 'assignment_id' => item.assignment_id, 'label' => row.fetch('label'), 'state' => item.state,
          'receipt' => item.receipt, 'error_code' => item.error_code }
      end }
  end
end

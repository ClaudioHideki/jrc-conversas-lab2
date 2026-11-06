class JrcRelationship::PortfolioBatch
  def initialize(context, params, review: nil)
    @context = context
    @params = params
    @review = review
  end

  def call
    raise Pundit::NotAuthorizedError unless @context.policy.manage?

    rows = selected_assignments
    operation = @params.require(:operation)
    raise ArgumentError, 'Unsupported portfolio operation' unless %w[assign activity playbook].include?(operation)
    raise Pundit::NotAuthorizedError if operation == 'assign' && !@context.policy.team?

    JrcRelationship::Assignment.transaction do
      authorize_transfer!(rows) if operation == 'assign'
      options = operation_options(operation, rows.count)
      rows.each do |record|
        @context.assignment(record.id, write: true)
        record.with_lock { apply!(record, operation, options) }
      end
    end
    rows.count
  end

  private

  def authorize_transfer!(rows)
    JrcRelationship::DistributionApproval.lock_configuration!(@context.account.id)
    raise ArgumentError, 'Complete responsibility transfer requires a reviewed proposal' if @params[:transfer_responsibilities] && !@review

    if @review
      assert_review_identity!(rows)
      JrcRelationship::DistributionApproval.new(@context).check!(@review)
    else
      JrcRelationship::DistributionApproval.direct_allowed!(@context, rows, owner_id: changed_owner_id(rows))
    end
  end

  def changed_owner_id(rows)
    owner_id = @params[:owner_id]
    owner_id if rows.any? { |row| row.owner_id.to_s != owner_id.to_s }
  end

  def assert_review_identity!(rows)
    expected = { 'account_id' => @context.account.id, 'actor_id' => @context.user.id, 'state' => 'running' }
    owner_id = @params[:owner_id].present? ? Integer(@params[:owner_id]) : nil
    inputs = { 'operation' => 'assign', 'owner_id' => owner_id }
    valid = @review.attributes.slice(*expected.keys) == expected && @review.inputs.slice(*inputs.keys) == inputs &&
            (rows.pluck(:id) - @review.inputs.fetch('ids')).empty?
    raise ArgumentError, 'Reviewed transfer identity mismatch' unless valid
  end

  def selected_assignments
    ids = @params.require(:ids)
    raise ArgumentError, 'Select between 1 and 50 customers' unless ids.is_a?(Array) && ids.size.between?(1, 50)

    rows = @context.assignments.where(id: ids).order(:id)
    raise ActiveRecord::RecordNotFound unless rows.count == ids.uniq.size

    rows
  end

  def operation_options(operation, count)
    request_id = @params.require(:request_id)
    case operation
    when 'assign'
      owner = @context.assignable_users.find(@params[:owner_id]) if @params[:owner_id].present?
      { owner: owner }
    when 'playbook'
      book = JrcRelationship::Playbook.where(account: @context.account, active: true).find(@params.require(:playbook_id))
      { book: book, **manual_playbook_options(book, request_id, count) }
    else { request_id: request_id }
    end
  end

  def apply!(record, operation, options)
    case operation
    when 'assign' then assign!(record, options[:owner])
    when 'activity'
      JrcRelationship::Workflow.new(@context).activity!(assignment: record, title: @params.require(:title),
                                                        due_at: @params.require(:due_at),
                                                        request_id: "portfolio:#{options[:request_id]}:#{record.id}")
    when 'playbook' then apply_playbook!(record, options)
    end
  end

  def assign!(record, owner)
    if @review&.inputs&.fetch('transfer_responsibilities', false)
      return JrcRelationship::ResponsibilityTransfer.new(@context, @review).call(record, owner)
    end

    before = { owner_id: record.owner_id }
    record.assign_attributes(owner: owner)
    work = JrcRelationship::PortfolioActionTransfer.prepare(@context, record)
    record.save!
    work&.apply!(owner)
    @context.audit!(record, before: before, after: { owner_id: owner&.id }, action: 'assignment_updated')
  end

  def apply_playbook!(record, options)
    book = options.fetch(:book)
    JrcRelationship::Playbooks.new(@context).run!(record, book.trigger_kind, playbook_id: book.id, **options.except(:book))
    @context.audit!(record, after: { playbook_id: book.id }, action: 'playbook_applied')
  end

  def manual_playbook_options(book, request_id, count)
    source_key = @params[:source_key].presence || "manual:#{request_id}"
    raise ArgumentError, 'Invalid playbook source key' unless source_key.is_a?(String) && source_key.length.between?(1, 180)

    approvals = validated_approvals(count)
    keys = book.steps.filter_map do |step|
      "playbook:#{book.id}:v#{book.version}:#{step['step_key']}:#{source_key}" if step['kind'] == 'flow'
    end
    raise ArgumentError, 'Unknown flow approval origin' if (approvals.keys - keys).any?

    { source_key: source_key, flow_approvals: approvals.permit(*keys).to_h }
  end

  def validated_approvals(count)
    approvals = @params.fetch(:flow_approvals, ActionController::Parameters.new)
    raise ArgumentError, 'Flow approvals must be an object' unless approvals.is_a?(ActionController::Parameters)
    raise ArgumentError, 'Flow approvals require one customer' if approvals.present? && count != 1

    approvals
  end
end

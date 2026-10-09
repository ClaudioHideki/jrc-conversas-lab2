class JrcRelationship::PortfolioBatch
  def initialize(context, params)
    @context = context
    @params = params
  end

  def call
    raise Pundit::NotAuthorizedError unless @context.policy.manage?

    rows = selected_assignments
    operation = @params.require(:operation)
    raise ArgumentError, 'Unsupported portfolio operation' unless %w[assign activity playbook].include?(operation)
    raise Pundit::NotAuthorizedError if operation == 'assign' && !@context.policy.team?

    options = operation_options(operation, rows.count)
    JrcRelationship::Assignment.transaction do
      rows.each do |record|
        @context.assignment(record.id, write: true)
        record.with_lock { apply!(record, operation, options) }
      end
    end
    rows.count
  end

  private

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
    before = { owner_id: record.owner_id }
    record.update!(owner: owner)
    record.actions.where(status: JrcRelationship::Action::ACTIVE_STATUSES).find_each do |action|
      action.update!(owner: owner)
      action.activity.update!(user: owner) if owner && action.activity
    end
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

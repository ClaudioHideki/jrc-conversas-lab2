class Api::V1::Accounts::Relationship::HandoffsController < Api::V1::Accounts::Relationship::BaseController
  def index
    rows = JrcRelationship::HandoffCase.where(account: Current.account, assignment_id: filtered_assignments.select(:id)).includes(:assignment)
    render json: { payload: rows.order(id: :desc).limit(100).map { |row| row.as_json.merge(customer_name: row.assignment.label) } }
  end

  def create
    assignment = relationship_context.assignment(params.require(:assignment_id), write: true)
    raise Pundit::NotAuthorizedError unless relationship_context.policy.team?

    source = creation_source(assignment)
    validate_creation_source!(source, assignment)
    row = JrcRelationship::HandoffCase.create_or_find_by!(account: Current.account, source_type: source.class.name, source_id: source.id) do |item|
      item.assignment = assignment
    end
    raise ArgumentError, 'Cannot change customer origin' if row.assignment_id != assignment.id

    relationship_context.audit!(row, action: 'handoff_prepared')
    render json: row, status: :created
  end

  def context
    row = cases.find(params[:id])
    render json: native_context(row)
  end

  def native_context(row)
    native = row.assignment.customer_context(relationship_context.member)
    source = row.source_type == 'JrcCrm::SalesOrder' ? native.orders.find(row.source_id) : native.projects.find(row.source_id)
    JrcRelationship::WorkContext.new(context: relationship_context, assignment: row.assignment).call.except(:_source_ids)
                                .merge(source: { type: source.class.name, id: source.id }, contacts: native.contacts.pluck(:id, :name))
  end

  def decide
    raise Pundit::NotAuthorizedError unless relationship_context.policy.team?

    row = cases.find(params[:id])
    row.with_lock do
      raise ArgumentError, 'Handoff already decided' unless row.status == 'pending'

      status = params.require(:status)
      raise ArgumentError, 'Invalid handoff decision' unless %w[accepted rejected].include?(status)

      checklist = validated_decision_checklist(row, status)
      record_decision!(row, status, checklist)
      start_accepted_handoff(row) if status == 'accepted'
      relationship_context.audit!(row, after: { status: status, reason: row.reason, checklist: checklist }, action: 'handoff_decided')
      render json: row
    end
  end

  private

  private :native_context

  def record_decision!(row, status, checklist)
    row.update!(status: status, reason: params.require(:reason), checklist: checklist, decided_by: Current.user, decided_at: Time.current)
  end

  def creation_source(assignment)
    customer = assignment.customer_context(relationship_context.member)
    case params.require(:source_type)
    when 'JrcCrm::SalesOrder' then customer.orders.find(params.require(:source_id))
    when 'JrcProjects::Project' then customer.projects.find(params.require(:source_id))
    else raise ArgumentError, 'Unsupported handoff origin'
    end
  end

  def validate_creation_source!(source, assignment)
    if source.is_a?(JrcCrm::SalesOrder)
      validate_order_eligibility!(source, assignment)
    elsif source.status != 'completed'
      raise ArgumentError, 'Implementation is not completed'
    end
  end

  def validate_order_eligibility!(source, assignment)
    reason = JrcRelationship::Eligibility.new(source, exception: assignment.settings['eligibility_exception']).reason
    raise ArgumentError, reason if reason
  end

  def validated_decision_checklist(row, status)
    native_context(row) # Revalidate the original native source before accepting.
    source = row.source_type.constantize.find(row.source_id)
    validate_order_eligibility!(source, row.assignment) if status == 'accepted' && source.is_a?(JrcCrm::SalesOrder)
    checklist = params.require(:checklist).permit(:contract, :products, :contacts, :objectives, :promises, :pending_items).to_h
    complete = %w[contract products contacts objectives promises pending_items].all? { |key| checklist[key] == true }
    raise ArgumentError, 'Review every handoff item before accepting' if status == 'accepted' && !complete

    checklist
  end

  def start_accepted_handoff(row)
    if relationship_context.configuration.effective_rules['handoff_acceptance_required']
      JrcRelationship::Handoff.call(row.source_type.constantize.find(row.source_id), actor: Current.user)
    else
      JrcRelationship::Playbooks.new(relationship_context).run!(row.assignment, 'onboarded')
    end
  end

  def cases
    JrcRelationship::HandoffCase.where(account: Current.account, assignment_id: relationship_context.assignments.select(:id))
  end
end

require 'digest'

class JrcRelationship::Workflow
  MODELS = { 'actions' => JrcRelationship::Action, 'risks' => JrcRelationship::RiskCase,
             'plans' => JrcRelationship::SuccessPlan, 'qbrs' => JrcRelationship::Qbr,
             'renewals' => JrcRelationship::Renewal, 'expansion' => JrcRelationship::ExpansionSignal,
             'surveys' => JrcRelationship::Survey }.freeze
  FIELDS = {
    'actions' => %w[reason status priority due_at result owner_id],
    'risks' => %w[kind severity reason status due_at outcome plan owner_id],
    'plans' => %w[title status target_on goals project_id contract_id product_id owner_id],
    'qbrs' => %w[title scheduled_at status agenda summary participants decisions owner_id meeting_url recording_url provider contact_id contract_id
                 product_id],
    'renewals' => %w[status proposed_mrr_cents],
    'expansion' => %w[title status product_id source_contract_id source_product_id potential_cents evidence],
    'surveys' => %w[kind]
  }.freeze

  def initialize(context)
    @context = context
  end

  def save(kind:, attributes:, id: nil)
    model = MODELS.fetch(kind)
    attrs = attributes.to_h.stringify_keys
    assignment = @context.assignment(attrs.fetch('assignment_id'), write: true)
    assignment.with_lock do
      raise ArgumentError, 'Renewal is created from an existing contract window' if kind == 'renewals' && !id

      record = id ? @context.records(model).lock.find(id) : model.new(account: @context.account, assignment: assignment, owner: assignment.owner)
      raise ArgumentError, 'Cannot change the customer origin' if record.assignment_id != assignment.id
      raise ActiveRecord::StaleObjectError.new(record, 'update') if id && attrs['lock_version'].to_s != record.lock_version.to_s

      audit_fields = audit_fields_for(kind)
      before = record.attributes.slice(*audit_fields)
      record.assign_attributes(attrs.slice(*FIELDS.fetch(kind)))
      if kind == 'actions' && attrs.key?('priority') && record.will_save_change_to_priority?
        record.metadata = record.metadata.merge('manual_priority' => true)
      end
      record.metadata = record.metadata.merge(attrs.slice('period_from', 'period_to', 'milestones', 'notes')) if %w[plans qbrs].include?(kind)
      record.agenda ||= @context.configuration(assignment).effective_rules['qbr_agenda_template'] if kind == 'qbrs'
      if kind == 'expansion' && attrs.key?('expansion_kind')
        raise ArgumentError, 'Invalid expansion kind' unless %w[upsell cross_sell usage new_product new_unit].include?(attrs['expansion_kind'])

        record.metadata = record.metadata.merge('expansion_kind' => attrs['expansion_kind'])
      end
      raise ArgumentError, 'Retention plan must be structured data' if kind == 'risks' && !record.plan.is_a?(Hash)

      if attrs.key?('owner_id') && attrs['owner_id'].to_s != before['owner_id'].to_s
        raise Pundit::NotAuthorizedError unless @context.policy.team?

        @context.assignable_users.find(record.owner_id) if record.owner_id
      end
      validate_links!(record)
      confirm_renewal!(record, attrs)
      record.source_key ||= "manual:#{attrs.fetch('request_id')}" if record.respond_to?(:source_key)
      record.kind ||= 'manual' if kind == 'actions'
      if kind == 'actions' && (record.new_record? || record.will_save_change_to_status?)
        record.completed_by = record.status == 'completed' ? @context.user : nil
        record.completed_at = record.status == 'completed' ? Time.current : nil
      end
      if kind == 'risks' && %w[churn retained no_action].include?(record.status)
        raise Pundit::NotAuthorizedError if record.status == 'churn' && !@context.policy.team?

        record.closed_at ||= Time.current
      end
      if kind == 'risks' && record.plan['concessions'].to_s != before.dig('plan', 'concessions').to_s && !@context.policy.team?
        raise Pundit::NotAuthorizedError
      end

      if kind == 'risks'
        approval = record.plan['approval_status']
        if approval != before.dig('plan', 'approval_status') && %w[approved rejected].include?(approval)
          raise Pundit::NotAuthorizedError unless @context.policy.team?

          record.plan = record.plan.merge('approved_by_id' => @context.user.id, 'approved_at' => Time.current.iso8601)
        end
        if record.status == 'retained' && record.plan['concessions'].present? && approval != 'approved'
          raise ArgumentError, 'Approve commercial concessions before confirming retention'
        end
      end
      if kind == 'expansion' && %w[approved converted].include?(record.status) && !record.deal_id
        raise ArgumentError, 'Approve expansion through the native CRM opportunity action'
      end

      raw_token = prepare_survey(record) if kind == 'surveys' && record.new_record?
      if kind == 'actions' && record.new_record?
        JrcRelationship::OperationalRouting.new(@context).prepare!(record, preserve_owner: attrs.key?('owner_id'))
      end
      capture_financial!(record, kind)
      record.save!
      JrcRelationship::RefreshJob.perform_later(@context.member.id, [assignment.id]) if kind == 'plans'
      if kind == 'actions' && record.saved_change_to_status? && %w[in_progress completed].include?(record.status)
        JrcOperations::SlaClock.new(record).mark_first_action!
      end
      project_action!(record) if kind == 'actions'
      if kind == 'actions' && record.activity
        fields = { due_at: record.due_at }
        fields[:user_id] = record.owner_id if record.owner_id
        fields.merge!(status: 'completed', completed_at: record.completed_at) if record.status == 'completed'
        fields[:status] = 'cancelled' if record.status == 'dismissed'
        fields.merge!(status: 'scheduled', completed_at: nil) if JrcRelationship::Action::ACTIVE_STATUSES.include?(record.status)
        record.activity.update!(fields)
      end
      sync_qbr!(record) if kind == 'qbrs'
      project_risk!(record) if kind == 'risks'
      if (kind == 'risks') && %w[churn retained].include?(record.status)
        assignment.update!(status: record.status == 'churn' ? 'churned' : 'active')
      end
      @context.audit!(record, before: before, after: record.attributes.slice(*audit_fields), action: id ? 'updated' : 'created')
      { record: record, survey_token: raw_token }
    end
  end

  def activity!(assignment:, title:, due_at:, request_id:, kind: 'task', owner_id: nil)
    raise Pundit::NotAuthorizedError unless JrcOperations::Access.crm?(@context.member)
    raise ArgumentError, 'Invalid activity type' unless %w[task meeting note follow_up call whatsapp email].include?(kind)

    key = "activity:#{request_id}"
    action = assignment.actions.find_or_initialize_by(source_key: key)
    return action.activity if action.persisted?

    action.assign_attributes(account: @context.account, owner: assignment.owner, kind: 'manual', reason: title, due_at: due_at)
    action.owner = @context.assignable_users.find(owner_id) if owner_id
    JrcRelationship::OperationalRouting.new(@context).prepare!(action, preserve_owner: owner_id.present?)
    action.owner ||= @context.user
    action.save!
    activity = project_action!(action, kind: kind)
    @context.audit!(activity, after: { title: title, due_at: due_at }, action: 'activity_created')
    activity
  end

  def project_action!(action, kind: 'task')
    return action.activity if action.activity
    return unless action.due_at && action.owner && JrcOperations::Access.crm?(@context.member)

    metadata = { relationship_assignment_id: action.assignment_id, relationship_action_id: action.id,
                 relationship_source_key: action.source_key }
    metadata[:relationship_sla_paused_at] = action.sla_paused_at.iso8601 if action.sla_paused_at
    activity = JrcCrm::Activity.create!(account: @context.account, user: action.owner,
                                        company: action.assignment.company, contact: action.assignment.contact,
                                        business_unit: action.assignment.business_unit,
                                        title: action.reason, activity_type: kind, due_at: action.due_at,
                                        metadata: metadata)
    action.update!(activity: activity)
    @context.audit!(activity, after: { action_id: action.id, due_at: activity.due_at }, action: 'agenda_projected')
    activity
  end

  def opportunity!(record, pipeline_id:, stage_id:, contact_id: nil)
    JrcRelationship::CommercialOpportunity.new(@context).call(record, pipeline_id: pipeline_id, stage_id: stage_id, contact_id: contact_id)
  end

  private

  def confirm_renewal!(record, attrs)
    return unless record.is_a?(JrcRelationship::Renewal) && record.status == 'won'

    outcome = JrcRelationship::RenewalOutcome.new(@context, record)
    contract = outcome.resolve(selected_id: attrs['renewed_contract_id'], lock: true)
    raise ArgumentError, 'Select a proven active signed successor contract before confirming renewal' unless contract

    record.metadata = record.metadata.merge(outcome.proof(contract))
  end

  def audit_fields_for(kind)
    fields = FIELDS.fetch(kind) + (kind == 'actions' ? %w[completed_at completed_by_id] : [])
    fields += %w[metadata] if %w[actions plans qbrs expansion renewals].include?(kind)
    fields += %w[financial_captured_at] if kind == 'risks'
    fields
  end

  def capture_financial!(record, kind)
    JrcRelationship::RiskFinancialSnapshot.capture!(record, @context) if kind == 'risks' && record.new_record?
  end

  def validate_links!(record)
    JrcRelationship::WorkflowReferences.new(@context).validate!(record)
  end

  def prepare_survey(record)
    frequency = @context.configuration(record.assignment).effective_rules['survey_frequency_days']
    recent = @context.records(JrcRelationship::Survey).where(assignment_id: record.assignment_id, kind: record.kind)
                     .where('created_at > ?', frequency.days.ago).exists?
    raise ArgumentError, 'Survey frequency limit reached' if recent

    token = SecureRandom.hex(32)
    record.metadata = record.metadata.merge('question' => @context.configuration(record.assignment).effective_rules["survey_question_#{record.kind}"])
    record.token_digest = Digest::SHA256.hexdigest(token)
    record.expires_at = 30.days.from_now
    token
  end

  def sync_qbr!(record)
    raise Pundit::NotAuthorizedError unless JrcOperations::Access.crm?(@context.member)

    unless record.activity
      record.update!(activity: activity!(assignment: record.assignment, title: record.title, due_at: record.scheduled_at,
                                         kind: 'meeting', owner_id: record.owner_id, request_id: "qbr:#{record.id}"))
    end
    activity_status = { 'scheduled' => 'scheduled', 'completed' => 'completed', 'canceled' => 'cancelled' }.fetch(record.status)
    record.activity.update!(title: record.title, user_id: record.owner_id || record.activity.user_id, due_at: record.scheduled_at, status: activity_status,
                            completed_at: record.status == 'completed' ? record.activity.completed_at || Time.current : nil)
    action = record.assignment.actions.find_by(activity_id: record.activity_id)
    if action
      action.update!(reason: record.title, owner_id: record.owner_id || action.owner_id, due_at: record.scheduled_at)
      status = { 'completed' => 'completed', 'canceled' => 'dismissed' }[record.status] ||
               (JrcRelationship::Action::ACTIVE_STATUSES.include?(action.status) ? action.status : 'open')
      save(kind: 'actions', id: action.id, attributes: { assignment_id: record.assignment_id, lock_version: action.lock_version,
                                                         status: status, result: record.summary }) if action.status != status
    end
    reconcile_qbr_commitments!(record)
    return unless record.status == 'completed'

    Array(record.decisions).each_with_index do |decision, index|
      next unless decision['title'].present?

      activity = activity!(assignment: record.assignment, title: decision['title'], due_at: decision['due_at'],
                           owner_id: decision['owner_id'].presence, request_id: "qbr:#{record.id}:decision:#{decision['decision_key'].presence || index}")
      commitment = record.assignment.actions.find_by!(activity_id: activity.id)
      save(kind: 'actions', id: commitment.id, attributes: { assignment_id: record.assignment_id, lock_version: commitment.lock_version,
                                                             reason: decision['title'], due_at: decision['due_at'], owner_id: decision['owner_id'].presence || commitment.owner_id })
      activity.update!(title: decision['title']) if activity.title != decision['title']
    end
  end

  def reconcile_qbr_commitments!(record)
    keys = Array(record.decisions).each_with_index.filter_map do |decision, index|
      "activity:qbr:#{record.id}:decision:#{decision['decision_key'].presence || index}" if decision['title'].present?
    end
    pending = @context.records(JrcRelationship::Action).where(assignment: record.assignment, status: JrcRelationship::Action::ACTIVE_STATUSES)
                      .where('source_key LIKE ?', "activity:qbr:#{record.id}:decision:%")
    pending = pending.where.not(source_key: keys) unless record.status == 'canceled'
    pending.each do |action|
      save(kind: 'actions', id: action.id, attributes: { assignment_id: record.assignment_id, lock_version: action.lock_version,
                                                         status: 'dismissed', result: 'Compromisso retirado da QBR ou reunião cancelada.' })
    end
  end

  def project_risk!(record)
    @context.assignment(record.assignment_id)
    key = "risk:#{record.id}"
    action = record.assignment.actions.where("metadata ->> 'relationship_risk_id' = ?", record.id.to_s).first ||
             record.assignment.actions.find_or_initialize_by(source_key: key)
    action.assign_attributes(account: @context.account, owner: record.owner, kind: 'retention', reason: record.reason,
                             due_at: record.due_at || action.due_at, metadata: record.metadata.merge('relationship_risk_id' => record.id))
    if action.new_record?
      action.priority = { 'critical' => 90, 'high' => 80, 'medium' => 50, 'low' => 20 }.fetch(record.severity)
      JrcRelationship::OperationalRouting.new(@context).prepare!(action, preserve_owner: record.owner_id.present?)
    end
    if %w[retained churn].include?(record.status)
      action.assign_attributes(status: 'completed', result: record.outcome, completed_at: Time.current, completed_by: @context.user)
    elsif record.status == 'no_action'
      action.status = 'dismissed'
    elsif %w[analyzing planned negotiating].include?(record.status)
      action.status = 'in_progress'
    end
    action.save!
    JrcOperations::SlaClock.new(action).mark_first_action! if %w[in_progress completed].include?(action.status)
    record.update_columns(due_at: action.due_at) unless record.due_at
    activity = project_action!(action)
    activity.update!(due_at: action.due_at, user_id: action.owner_id || activity.user_id) if activity
    activity.update!(status: 'completed', completed_at: action.completed_at) if activity && action.status == 'completed'
    activity.update!(status: 'cancelled') if activity && action.status == 'dismissed'
  end

  public :project_risk!
end

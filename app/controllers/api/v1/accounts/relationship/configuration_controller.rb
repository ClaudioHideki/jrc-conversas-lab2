class Api::V1::Accounts::Relationship::ConfigurationController < Api::V1::Accounts::Relationship::BaseController
  before_action do
    raise Pundit::NotAuthorizedError unless relationship_context.policy.configure?
  end

  def show
    scope_key = params.fetch(:scope_key, 'account')
    relationship_context.authorize_configuration_scope!(scope_key)
    record = JrcRelationship::Configuration.find_or_initialize_by(account: Current.account, scope_key: scope_key)
    raise ActiveRecord::RecordInvalid, record unless record.valid?

    render json: configuration_payload(record)
  end

  def update
    record = Current.account.with_lock do
      @relationship_context = JrcRelationship::Context.new(Current.account_user)
      raise Pundit::NotAuthorizedError unless relationship_context.policy.configure?

      scope = params.fetch(:scope_key, 'account')
      relationship_context.authorize_configuration_scope!(scope)
      row = JrcRelationship::Configuration.find_or_initialize_by(account: Current.account, scope_key: scope)
      update_configuration!(row)
      row
    end
    render json: configuration_payload(record)
  end

  def playbooks
    render json: { payload: JrcRelationship::Playbook.where(account: Current.account).includes(:versions).order(:id).limit(100).map do |row|
      row.as_json.merge(history: row.versions.order(version: :desc).limit(50).as_json)
    end }
  end

  def save_playbook
    attrs = playbook_attributes
    record = find_playbook
    record.transaction do
      record.lock! if record.persisted?
      update_playbook!(record, attrs)
    end
    render json: record
  end

  def playbook_options
    rows = relationship_context.assignments.order(:id).limit(250)
    payload = { assignments: rows.map { |row| [row.id, row.label] }, flows: JrcRelationship::PlaybookFlow.catalog(relationship_context) }
    payload.merge!(assignment_flow_options) if params[:assignment_id].present?
    render json: payload
  end

  def playbook_preview
    attrs = playbook_attributes
    validate_flow_steps!(attrs[:steps])
    assignment = relationship_context.assignment(params.require(:assignment_id), write: true)
    book = find_playbook
    expected = params.dig(:playbook, :version)
    raise ActiveRecord::StaleObjectError.new(book, 'preview') if book.persisted? && expected.to_s != book.version.to_s

    book.assign_attributes(attrs)
    render json: JrcRelationship::PlaybookPreview.new(relationship_context)
                                                 .call(assignment: assignment, playbook: book, source_key: params.require(:source_key))
  end

  def playbook_executions
    rows = JrcRelationship::PlaybookExecution.where(account: Current.account, assignment_id: relationship_context.assignments.select(:id))
    render json: { payload: rows.includes(:assignment).order(id: :desc).limit(100).select { |row| execution_visible?(row) }
                                .map { |row| execution_payload(row) } }
  end

  private

  def execution_payload(row)
    results = JrcRelationship::PlaybookFlow.new(relationship_context).projection(execution: row)
    row.as_json.merge(customer_name: row.assignment.label, snapshot: row.snapshot.merge('results' => results))
  end

  def configuration_payload(record)
    { scope_key: record.scope_key, version: record.version, weights: record.effective_weights, rules: record.effective_rules,
      history: configuration_history(record) }
  end

  def configuration_history(record)
    return [] unless record.persisted?

    record.versions.order(version: :desc).limit(50).as_json(only: [:version, :weights, :rules, :actor_id, :created_at])
  end

  def find_playbook
    return JrcRelationship::Playbook.where(account: Current.account).find(params[:id]) if params[:id]

    JrcRelationship::Playbook.new(account: Current.account)
  end

  def update_playbook!(record, attrs)
    validate_playbook_version!(record)

    before = record.attributes.slice('name', 'trigger_kind', 'active', 'steps', 'conditions')
    capture_playbook_version!(record) if record.persisted?
    record.active = false if record.new_record?
    record.assign_attributes(attrs)
    validate_flow_steps!(record.steps) if record.new_record? || record.will_save_change_to_steps?
    record.version += 1 if record.persisted?
    record.save!
    capture_playbook_version!(record)
    audit_playbook!(record, before)
  end

  def validate_playbook_version!(record)
    raise ActiveRecord::StaleObjectError.new(record, 'update') if record.persisted? && params.dig(:playbook, :version).to_s != record.version.to_s
  end

  def audit_playbook!(record, before)
    after = record.attributes.slice('name', 'trigger_kind', 'active', 'steps', 'conditions')
    JrcCustomers::Audit.record!(account: Current.account, actor: Current.user, resource: record, event_type: 'relationship_updated',
                                from_value: before, to_value: after, metadata: { action: 'playbook_configured' })
  end

  def assignment_flow_options
    assignment = relationship_context.assignment(params[:assignment_id], write: true)
    customer = assignment.customer_context(relationship_context.member)
    contacts = customer.contacts.select { |row| ContactPolicy.new(relationship_context.to_h, row).show? }
    conversations = customer.conversations.where(contact_id: contacts.map(&:id)).order(id: :desc).limit(250)
    { business_unit_id: assignment.business_unit_id, contacts: contacts.map { |row| [row.id, row.name] },
      conversations: conversation_options(conversations) }
  end

  def conversation_options(conversations)
    conversations.map { |row| { id: row.id, display_id: row.display_id, contact_id: row.contact_id } }
  end

  def update_configuration!(record)
    record.lock! if record.persisted?
    expected = params.require(:version).to_i
    raise ActiveRecord::StaleObjectError.new(record, 'update') unless expected == record.version

    previous = configuration_version(record)
    record.assign_attributes(weights: params.require(:weights).to_unsafe_h, rules: params.require(:rules).to_unsafe_h, version: expected + 1)
    record.save!
    record.capture_version!(previous, actor: Current.user)
    current = configuration_version(record)
    record.capture_version!(current, actor: Current.user)
    audit_configuration!(record, previous, current)
  end

  def audit_configuration!(record, previous, current)
    JrcCustomers::Audit.record!(account: Current.account, actor: Current.user, resource: record, event_type: 'relationship_updated',
                                from_value: previous, to_value: current, metadata: { action: 'configuration_versioned', scope_key: record.scope_key })
  end

  def configuration_version(record)
    { 'version' => record.version, 'weights' => record.effective_weights, 'rules' => record.effective_rules }
  end

  def playbook_attributes
    params.require(:playbook).permit(:name, :trigger_kind, :active,
                                     steps: [:kind, :title, :after_days, :step_key, *JrcRelationship::PlaybookSteps::FLOW_FIELDS],
                                     conditions: [:field, :operator, :value])
  end

  def validate_flow_steps!(steps)
    Array(steps).map { |step| step.to_h.with_indifferent_access }.select { |step| step[:kind] == 'flow' }.each do |step|
      validate_flow_step!(step)
    end
  end

  def validate_flow_step!(step)
    raise Pundit::NotAuthorizedError unless relationship_context.member.administrator? && JrcFlows::Access.enabled?(Current.account)

    flow = JrcFlow.where(account: Current.account, status: 'active', engine: 'native', connection_id: nil).find(step[:flow_id])
    conversation = customer_visibility.conversations.find(step[:conversation_id])
    JrcOperations::Access.contact!(Current.account_user, step[:contact_id])
    validate_flow_contact!(conversation, step)

    relationship_context.authorize_configuration_scope!("unit:#{step[:business_unit_id]}") if step[:business_unit_id].present?
    validate_flow_pin!(flow, step)
  end

  def validate_flow_contact!(conversation, step)
    raise Pundit::NotAuthorizedError unless conversation.contact_id.to_s == step[:contact_id].to_s
    return unless step.key?(:message_id)

    JrcRelationship::PlaybookFlowInput.find!(account: Current.account, conversation: conversation,
                                            contact_id: conversation.contact_id, message_id: step[:message_id])
  end

  def validate_flow_pin!(flow, step)
    return if flow.lock_version.to_s == step[:flow_lock_version].to_s && JrcRelationship::PlaybookFlow.definition_digest(flow) == step[:flow_digest]

    raise ArgumentError, 'Published flow definition changed'
  end

  def customer_visibility
    JrcCustomers::Visibility.new(account: Current.account, user: Current.user, account_user: Current.account_user)
  end

  def execution_visible?(row)
    Array(row.snapshot['results']).all? do |result|
      next true unless result['resource_id']

      if result['resource_type'] == 'JrcFlowRun'
        next JrcRelationship::PlaybookFlow.visible_run?(context: relationship_context, assignment: row.assignment, id: result['resource_id'])
      end

      native_execution_visible?(result)
    end
  end

  def native_execution_visible?(result)
    model = JrcRelationship::Workflow::MODELS.values.find { |candidate| candidate.name == result['resource_type'] }
    return false unless model && relationship_context.records(model).exists?(id: result['resource_id'])

    result['activity_id'].blank? || customer_visibility.crm(Current.account.jrc_crm_activities, owner: :user_id).exists?(id: result['activity_id'])
  end

  def capture_playbook_version!(record)
    record.versions.create_or_find_by!(account: Current.account, version: record.version) do |version|
      version.actor = Current.user
      version.payload = record.snapshot
    end
  end
end

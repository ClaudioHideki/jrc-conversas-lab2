class Api::V1::Accounts::Relationship::ConfigurationController < Api::V1::Accounts::Relationship::BaseController
  before_action do
    raise Pundit::NotAuthorizedError unless relationship_context.policy.configure?
  end

  def show
    scope_key = params.fetch(:scope_key, 'account')
    record = JrcRelationship::Configuration.find_or_initialize_by(account: Current.account, scope_key: scope_key)
    raise ActiveRecord::RecordInvalid, record unless record.valid?
    render json: { scope_key: record.scope_key, version: record.version, weights: record.effective_weights, rules: record.effective_rules,
      history: record.persisted? ? record.versions.order(version: :desc).limit(50).as_json(only: [:version, :weights, :rules, :actor_id, :created_at]) : [] }
  end

  def update
    record = JrcRelationship::Configuration.find_or_initialize_by(account: Current.account, scope_key: params.fetch(:scope_key, 'account'))
    record.transaction do
      record.lock! if record.persisted?
      expected = params.require(:version).to_i
      raise ActiveRecord::StaleObjectError.new(record, 'update') unless expected == record.version
      previous = { 'version' => record.version, 'weights' => record.effective_weights, 'rules' => record.effective_rules }
      record.assign_attributes(weights: params.require(:weights).to_unsafe_h, rules: params.require(:rules).to_unsafe_h, version: expected + 1)
      record.save!
      record.capture_version!(previous, actor: Current.user)
      current = { 'version' => record.version, 'weights' => record.effective_weights, 'rules' => record.effective_rules }
      record.capture_version!(current, actor: Current.user)
      JrcCustomers::Audit.record!(account: Current.account, actor: Current.user, resource: record, event_type: 'relationship_updated',
        from_value: previous, to_value: current, metadata: { action: 'configuration_versioned', scope_key: record.scope_key })
    end
    render json: { scope_key: record.scope_key, version: record.version, weights: record.effective_weights, rules: record.effective_rules,
      history: record.persisted? ? record.versions.order(version: :desc).limit(50).as_json(only: [:version, :weights, :rules, :actor_id, :created_at]) : [] }
  end

  def playbooks
    render json: { payload: JrcRelationship::Playbook.where(account: Current.account).order(:id).limit(100) }
  end

  def save_playbook
    attrs = params.require(:playbook).permit(:name, :trigger_kind, :active, steps: [:kind, :title, :after_days, :step_key], conditions: [:field, :operator, :value])
    record = params[:id] ? JrcRelationship::Playbook.where(account: Current.account).find(params[:id]) : JrcRelationship::Playbook.new(account: Current.account)
    record.transaction do
      before = record.attributes.slice('name', 'trigger_kind', 'active', 'steps', 'conditions')
      record.update!(attrs)
      JrcCustomers::Audit.record!(account: Current.account, actor: Current.user, resource: record, event_type: 'relationship_updated', from_value: before,
        to_value: record.attributes.slice('name', 'trigger_kind', 'active', 'steps', 'conditions'), metadata: { action: 'playbook_configured' })
    end
    render json: record
  end
end

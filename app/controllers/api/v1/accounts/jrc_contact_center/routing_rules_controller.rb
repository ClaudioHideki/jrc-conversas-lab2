# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::RoutingRulesController < Api::V1::Accounts::JrcContactCenter::BaseController
  def index
    authorize_contact_center!(:configure?)
    response.headers['Cache-Control'] = 'no-store'
    rules = search_records(scoped_rules, fields: %w[rule_key source_value])
    rules = rules.where(state: params[:state]) if JrcContactCenter::RoutingRule::STATES.include?(params[:state])
    rules = rules.where(kind: params[:kind]) if JrcContactCenter::RoutingRule::KINDS.include?(params[:kind])
    render json: list_payload(rules.order(version: :desc, priority: :asc, rule_key: :asc)) { |record| serialize(record) }
  end

  def show
    authorize_contact_center!(:configure?)
    response.headers['Cache-Control'] = 'no-store'
    render json: base_payload.merge(item: serialize(scoped_rules.find(params[:id])))
  end

  def create
    with_current_configuration_authority do
      rule = JrcContactCenter::RoutingRule.create!(
        routing_params.merge(account: Current.account, created_by_account_user: Current.account_user)
      )
      JrcContactCenter::ConfigurationAudit.write!(
        rule, action: 'create', before: nil, after: JrcContactCenter::ConfigurationAuditSnapshot.capture(rule)
      )
      render json: base_payload.merge(item: serialize(rule)), status: :created
    end
  end

  def update
    with_current_configuration_authority do
      rule = scoped_rules.lock.find(params[:id])
      raise JrcContactCenter::OperationError.new('published_rule_immutable', status: :conflict) if rule.state == 'published'

      JrcContactCenter::ConfigurationRevision.check!(rule, params[:expected_revision]) if params.key?(:expected_revision)
      before = JrcContactCenter::ConfigurationAuditSnapshot.capture(rule)
      rule.update!(routing_params)
      JrcContactCenter::ConfigurationAudit.write!(
        rule, action: 'update', before: before, after: JrcContactCenter::ConfigurationAuditSnapshot.capture(rule)
      )
      render json: base_payload.merge(item: serialize(rule))
    end
  end

  private

  def with_current_configuration_authority
    JrcContactCenter::AuthorityTransaction.call(account: Current.account, member: Current.account_user) do
      Current.user.reload
      raise Pundit::NotAuthorizedError unless Current.user.active_for_authentication?

      @contact_center_access = JrcContactCenter::AccessScope.new(user_context: pundit_user)
      raise Pundit::NotAuthorizedError unless contact_center_access.policy.configure?

      yield
    end
  end

  def scoped_rules
    JrcContactCenter::OrganizationalScope.new(account: Current.account, account_user: Current.account_user)
                                         .records(JrcContactCenter::RoutingRule.where(account: Current.account),
                                                  unit_column: :target_unit_id, queue_column: :target_queue_id)
  end

  def routing_params
    permitted = params.require(:routing_rule).permit(:version, :rule_key, :kind, :source_value, :target_unit_id, :target_queue_id, :priority,
                                                     :state, :starts_at, :ends_at, conditions: {})
    contact_center_access.units.find(permitted[:target_unit_id]) if permitted[:target_unit_id].present?
    contact_center_access.queues.find(permitted[:target_queue_id]) if permitted[:target_queue_id].present?
    if permitted[:state] == 'published'
      authorize_contact_center!(:publish?)
      raise JrcContactCenter::Providers::BaseAdapter::CapabilityUnavailable, 'configuration_publication'
    end
    permitted
  end

  def serialize(record)
    attributes = record.as_json(only: %i[id version rule_key kind source_value target_unit_id target_queue_id priority state starts_at ends_at
                                         conditions created_by_account_user_id created_at updated_at])
    attributes.merge('revision' => JrcContactCenter::ConfigurationRevision.token(record))
  end
end

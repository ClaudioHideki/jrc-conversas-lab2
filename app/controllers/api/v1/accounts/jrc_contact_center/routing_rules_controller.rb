# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::RoutingRulesController < Api::V1::Accounts::JrcContactCenter::BaseController
  def index
    authorize_contact_center!(:configure?)
    rules = scoped_rules.order(version: :desc, priority: :asc, rule_key: :asc)
    render json: base_payload.merge(items: rules.map { |record| serialize(record) })
  end

  def create
    authorize_contact_center!(:configure?)
    rule = JrcContactCenter::RoutingRule.create!(
      routing_params.merge(account: Current.account, created_by_account_user: Current.account_user)
    )
    render json: base_payload.merge(item: serialize(rule)), status: :created
  end

  def update
    authorize_contact_center!(:configure?)
    rule = scoped_rules.find(params[:id])
    rule.update!(routing_params)
    render json: base_payload.merge(item: serialize(rule))
  end

  private

  def scoped_rules
    JrcContactCenter::RoutingRule.where(account: Current.account)
  end

  def routing_params
    permitted = params.require(:routing_rule).permit(:version, :rule_key, :kind, :source_value, :target_unit_id, :target_queue_id, :priority,
                                                     :state, :starts_at, :ends_at, conditions: {})
    JrcContactCenter::Unit.where(account: Current.account).find(permitted[:target_unit_id]) if permitted[:target_unit_id].present?
    JrcContactCenter::Queue.where(account: Current.account).find(permitted[:target_queue_id]) if permitted[:target_queue_id].present?
    permitted
  end

  def serialize(record)
    record.as_json(only: %i[id version rule_key kind source_value target_unit_id target_queue_id priority state starts_at ends_at conditions
                            created_by_account_user_id created_at updated_at])
  end
end

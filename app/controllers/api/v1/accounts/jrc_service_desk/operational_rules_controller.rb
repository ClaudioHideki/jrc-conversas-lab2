# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::OperationalRulesController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  def index
    authorize ::JrcServiceDesk::OperationalRuleVersion, :index?
    values = ::JrcServiceDesk::Input.attributes(query_values, %w[unit_id kind])
    kind = values.fetch('kind')
    raise ArgumentError unless ::JrcServiceDesk::OperationalRuleContract::KINDS.include?(kind)

    unit = operational_context.unit_scope.find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    ::JrcServiceDesk::OperationalRuleAccess.require!(operational_context, kind, unit)
    records = policy_scope(::JrcServiceDesk::OperationalRuleVersion).where(unit_id: unit.id, kind: kind).order(version: :desc).limit(100)
    render json: base_payload.merge(unit_id: unit.id.to_s, kind: kind, versions: records.map { |row| projection(row) })
  end

  def create
    values = body_values(%w[unit_id kind definition enabled expected_version])
    unit = operational_context.unit_scope.find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    authorize ::JrcServiceDesk::OperationalRuleVersion.new(account: Current.account, unit: unit, kind: values.fetch('kind')), :create?
    row = ::JrcServiceDesk::PublishOperationalRulesService.new(user_context: pundit_user).call(
      unit_id: unit.id, kind: values.fetch('kind'), definition: values.fetch('definition'),
      enabled: values.fetch('enabled'), expected_version: values.fetch('expected_version')
    )
    render json: base_payload.merge(unit_id: unit.id.to_s, kind: row.kind, version: projection(row)), status: :created
  end

  def intake_options
    values = ::JrcServiceDesk::Input.attributes(query_values, %w[unit_id])
    unit = operational_context.unit_scope.find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    authorize ::JrcServiceDesk::Ticket.new(account: Current.account, unit: unit), :create?
    rule = ::JrcServiceDesk::OperationalRuleVersion.current(account_id: Current.account.id, unit_id: unit.id, kind: 'priority_matrix')
    rows = rule&.enabled? ? rule.definition.fetch('rules') : []
    render json: base_payload.merge(unit_id: unit.id.to_s, impacts: rows.map { |row| row['match']['impact'] }.compact.uniq.sort,
                                    urgencies: rows.map { |row| row['match']['urgency'] }.compact.uniq.sort)
  end

  private

  def operational_context
    @operational_context ||= ::JrcServiceDesk::OperationalContext.new(pundit_user)
  end

  def projection(row)
    authorize row, :show?
    { id: row.id.to_s, version: row.version, enabled: row.enabled, definition: row.definition,
      digest: row.digest, published_by_membership_id: row.published_by_membership_id.to_s, created_at: row.created_at.iso8601(6) }
  end
end

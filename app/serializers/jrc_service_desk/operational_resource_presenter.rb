# frozen_string_literal: true

class JrcServiceDesk::OperationalResourcePresenter
  def initialize(context:)
    @context = JrcServiceDesk::OperationalContext.new(context)
  end

  def call(row)
    policy = JrcServiceDesk::OperationalResourcePolicy.new(@context.to_h, row)
    raise Pundit::NotAuthorizedError unless policy.show?

    identity(row).merge(ownership(row)).merge(planning(row)).merge(
      details: row.details, history: history(row), lock_version: row.lock_version,
      ticket_ids: visible_ticket_ids(row.resource_ticket_links.select(:ticket_id)),
      permissions: { show: true, update: policy.update?, destroy: policy.destroy? }
    )
  end

  private

  def identity(row)
    { id: row.id.to_s, account_id: row.account_id.to_s, unit_id: row.unit_id.to_s, name: row.name,
      code: row.code, resource_kind: row.resource_kind, description: row.description, priority: row.priority, state: row.state }
  end

  def ownership(row)
    { owner_account_user_id: row.owner_membership&.account_user_id&.to_s,
      company_id: customer_allowed? ? row.company_id&.to_s : nil, approval_id: approval_allowed?(row) ? row.approval_id&.to_s : nil }
  end

  def planning(row)
    { planned_start_at: row.planned_start_at&.iso8601(6), planned_end_at: row.planned_end_at&.iso8601(6) }
  end

  def visible_ticket_ids(ids)
    Pundit.policy_scope!(@context.to_h, JrcServiceDesk::Ticket).where(id: ids).order(:id).pluck(:id).map(&:to_s)
  end

  def customer_allowed?
    @context.capability?(:customers_view) && JrcCustomers::DirectoryPolicy.new(@context.to_h, :directory).access?
  end

  def approval_allowed?(row)
    row.approval && JrcServiceDesk::TicketApprovalPolicy.new(@context.to_h, row.approval).show?
  end

  def history(row)
    row.history.map do |entry|
      values = entry.deep_dup
      values.fetch('attributes', {}).delete('company_id') unless customer_allowed?
      values.fetch('attributes', {}).delete('approval_id') unless approval_allowed?(row)
      filter_ticket_history!(values) if values.dig('attributes', 'ticket_ids')
      values
    end
  end

  def filter_ticket_history!(values)
    values['attributes']['ticket_ids'] = visible_ticket_ids(values['attributes']['ticket_ids'])
  end
end

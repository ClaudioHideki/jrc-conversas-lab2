# frozen_string_literal: true

class JrcServiceDesk::OperationsBoardQuery
  MODELS = { 'tasks' => JrcServiceDesk::TicketTask, 'approvals' => JrcServiceDesk::TicketApproval,
             'incidents' => JrcServiceDesk::Incident, 'problems' => JrcServiceDesk::Incident }.freeze

  def initialize(context:, parameters:)
    @context = JrcServiceDesk::OperationalContext.new(context)
    @values = JrcServiceDesk::Input.attributes(parameters, %w[kind unit_id operator_company_id page per_page status query owner_account_user_id])
  end

  def call
    kind = @values.fetch('kind')
    model = MODELS.fetch(kind)
    Pundit.authorize(@context.to_h, model, :index?)
    rows = records(model, kind)
    paging = JrcServiceDesk::QueryParameters.new(@values.slice('page', 'per_page'))
    presenter = JrcServiceDesk::OperationsPresenter.new(context: @context)
    { kind: kind, items: rows.offset(paging.offset).limit(paging.per_page).map { |row| presenter.call(kind, row) },
      meta: { page: paging.page, per_page: paging.per_page, total: rows.count } }
  end

  private

  def records(model, kind)
    rows = Pundit.policy_scope!(@context.to_h, model)
    units = @context.unit_scope
    if @values['operator_company_id']
      company_id = JrcServiceDesk::Input.id(@values['operator_company_id'])
      raise ActiveRecord::RecordNotFound unless units.exists?(operator_company_id: company_id)

      units = units.where(operator_company_id: company_id)
      rows = rows.where(unit_id: units.select(:id))
    end
    if @values['unit_id']
      unit = units.find(JrcServiceDesk::Input.id(@values['unit_id']))
      rows = rows.where(unit_id: unit.id)
    end
    rows = rows.where(resource_kind: kind == 'problems' ? 'problem' : 'incident') if model == JrcServiceDesk::Incident
    if @values['status']
      allowed = { 'tasks' => JrcServiceDesk::TicketTask::STATUSES, 'approvals' => JrcServiceDesk::TicketApproval::STATUSES,
                  'incidents' => JrcServiceDesk::Incident::STATUSES, 'problems' => JrcServiceDesk::Incident::STATUSES }.fetch(kind)
      raise ArgumentError unless allowed.include?(@values['status'])

      rows = rows.where(status: @values['status'])
    end
    if @values['owner_account_user_id']
      raise ArgumentError unless model == JrcServiceDesk::Incident

      owner = @context.account.account_users.find(JrcServiceDesk::Input.id(@values['owner_account_user_id']))
      rows = rows.where(owner_membership_id: JrcServiceDesk::UnitMembership.where(account_user: owner).select(:id))
    end
    if @values['query']
      raise ArgumentError unless @values['query'].is_a?(String) && @values['query'].size <= 200

      term = "%#{ActiveRecord::Base.sanitize_sql_like(@values['query'])}%"
      rows = rows.where('title ILIKE ?', term)
    end
    rows.order(created_at: :desc, id: :desc)
  end
end

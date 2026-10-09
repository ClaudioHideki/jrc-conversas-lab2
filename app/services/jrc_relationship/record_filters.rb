class JrcRelationship::RecordFilters
  def initialize(model, params, renewal_rules: nil)
    @model = model
    @params = params
    @renewal_rules = renewal_rules
  end

  def identity_scope(scope)
    return scope if @model == JrcRelationship::Survey

    scope = scope.where(id: @params[:record_id]) if @params[:record_id].present?
    scope = scope.where(status: @params[:record_status]) if @params[:record_status].present? && @model.column_names.include?('status')
    scope
  end

  def renewal_scope(scope)
    return scope unless @model == JrcRelationship::Renewal && @params[:renewal_window].present?

    JrcRelationship::RenewalWindow.scope(scope, @params[:renewal_window], rules: @renewal_rules)
  end

  def operational_scope(scope)
    scope = overdue_scope(scope)
    scope = scope.where(kind: @params[:type]) if @params[:type].present? && @model.column_names.include?('kind')
    scope = priority_scope(scope)
    period_scope(scope)
  end

  private

  def priority_scope(scope)
    return scope unless @params[:priority].present? && @model.column_names.include?('priority')

    scope.where('priority >= ?', @params[:priority].to_i.clamp(0, 100))
  end

  def overdue_scope(scope)
    return scope unless @params[:overdue] == 'true' && @model.column_names.include?('due_at')

    scope = scope.where('due_at < ?', Time.current)
    @model == JrcRelationship::Action ? scope.where(sla_paused_at: nil) : scope
  end

  def period_scope(scope)
    return scope unless @params[:from].present? && @model.column_names.include?('due_at')

    from = Date.iso8601(@params[:from])
    to = Date.iso8601(@params.fetch(:to, @params[:from]))
    raise ArgumentError, 'Invalid period' if to < from || (to - from).to_i > 366

    scope.where(due_at: from.beginning_of_day..to.end_of_day)
  end
end

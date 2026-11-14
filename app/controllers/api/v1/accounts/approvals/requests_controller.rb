class Api::V1::Accounts::Approvals::RequestsController < Api::V1::Accounts::Approvals::BaseController
  def index
    rows = request_relation.includes(:policy_version, :decisions, requester: :user).filter_map { |record| visible_row(record) }
    render json: paginated(rows)
  end

  def summary
    response.headers['Cache-Control'] = 'no-store'
    zone = Time.find_zone!(params[:time_zone].presence || 'UTC')
    now = Time.current.in_time_zone(zone)
    period = now.beginning_of_month...now.next_month.beginning_of_month
    today = now.beginning_of_day...now.tomorrow.beginning_of_day
    counts = { pending: 0, approved: 0, rejected: 0, due_today: 0 }
    request_relation(except_state: true).includes(:policy_version, :decisions, requester: :user).each do |record|
      next unless summary_visible?(record)

      counts[:pending] += 1 if record.state == 'pending'
      counts[:due_today] += 1 if record.state == 'pending' && record.expires_at && today.cover?(record.expires_at)
      decision_at = record.decisions.max_by(&:created_at)&.created_at
      next unless decision_at && period.cover?(decision_at)

      counts[:approved] += 1 if record.state == 'approved'
      counts[:rejected] += 1 if record.state == 'rejected'
    end
    render json: counts.merge(time_zone: zone.name, period_start: period.begin.iso8601, period_end: period.end.iso8601)
  end

  def show
    record = readable_request
    decisions = record.decisions.includes(actor: :user, principal: :user).order(:id).map do |decision|
      values = decision.attributes.slice('id', 'step_code', 'decision', 'reason', 'cycle', 'created_at')
      values.merge('actor_name' => decision.actor.user.name,
                   'delegated_from_name' => decision.delegation_id && decision.principal.user.name)
    end
    render json: request_payload(record).merge(decisions: decisions, review_directions: service(JrcApprovals::ReviewDirections).options(record), adjustment: service(JrcApprovals::Adjustments).options(record),
                                               allowed_decisions: JrcApprovals::DecisionOptions.call(
                                                 account: Current.account, user: Current.user, record: record
                                               ))
  end

  def create
    values = params.require(:approval_request).permit(:key, :resource_id, :idempotency_key).to_h.symbolize_keys
    records = if JrcApprovals::CommercialCatalog::EVENTS.key?(values[:key])
                service(JrcApprovals::CommercialGate).request!(**values)
              else
                service(JrcApprovals::Requests).create!(**values)
              end
    render json: records.map { |record| request_payload(record) }, status: :created
  end

  def simulate
    context = params[:context]&.permit(:issuer_company_id, :business_unit_id, values: {})&.to_h
    result = service(JrcApprovals::Simulation).call(key: params[:key], resource_id: params[:resource_id], context: context)
    result[:versions].each { |item| add_selection_details(item) }
    render json: result
  end

  def decide
    values = params.require(:decision).permit(:step_code, :decision, :reason, :expected_version, :idempotency_key,
      :delegation_id, :own_delegation_id).to_h.symbolize_keys
    record = service(JrcApprovals::Decisions).call(request_id: params[:id], **values)
    render json: record.attributes.slice('id', 'request_id', 'actor_id', 'principal_id', 'step_code', 'decision', 'reason', 'cycle', 'created_at')
  end

  def transition
    values = params.permit(:action_key, :expected_version, :reason).to_h.symbolize_keys
    record = service(JrcApprovals::Requests).transition!(request_id: params[:id], action: values[:action_key],
                                                         expected_version: values[:expected_version], reason: values[:reason])
    render json: request_payload(record)
  end

  def adjust
    input = params.require(:adjustment)
    changes = input.require(:changes)
    raise JrcApprovals::Error, 'INVALID_ADJUSTMENT_FIELDS' unless (changes.keys - JrcApprovals::Adjustments::FIELDS).empty?

    values = input.permit(:mode, :reason, :expected_version, :idempotency_key, :step_code, :delegation_id, :own_delegation_id).to_h.symbolize_keys
    record = service(JrcApprovals::Adjustments).call(request_id: params[:id], changes: changes.permit(*JrcApprovals::Adjustments::FIELDS).to_h, **values)
    readable = JrcApprovals::RequestVisibility.authorize!(account: Current.account, user: Current.user, record: record)
    render json: { saved: true, request: readable && request_payload(record) }
  rescue Pundit::NotAuthorizedError
    # A successful save can route the new value to a different authority. Never disclose its request.
    raise unless record

    render json: { saved: true, request: nil }
  rescue JrcCrm::CommercialFinancials::InvalidTerms
    render json: { error: 'INVALID_COMMERCIAL_TERMS' }, status: :unprocessable_entity
  end

  def review_direction
    response.headers['Cache-Control'] = 'no-store'
    input = params.require(:review_direction).permit(:kind, :text, :expected_version, :idempotency_key, :step_code,
      :delegation_id, :own_delegation_id).to_h.symbolize_keys
    render json: service(JrcApprovals::ReviewDirections).call(request_id: params[:id], **input)
  end

  def audit
    record = readable_request
    authorization.authorize!('view_audit', company_id: record.issuer_company_id, unit_id: record.business_unit_id)
    rows = JrcApprovals::AuditEvent.where(account_id: Current.account.id, request_id: record.id).order(:id)
                                   .map { |event| event.attributes.slice('id', 'actor_id', 'event_type', 'data', 'created_at') }
    render json: paginated(rows)
  end

  def report
    bytes = service(JrcApprovals::RequestReport).call(params[:id])
    response.headers['Cache-Control'] = 'no-store'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    send_data bytes, filename: "approval-#{params[:id].to_i}-report.json", type: 'application/json', disposition: 'attachment'
  end

  private

  def request_relation(except_state: false)
    fields = %w[state issuer_company_id business_unit_id module_key event_key resource_type resource_id]
    fields -= ['state'] if except_state
    relation = filtered(JrcApprovals::Request.where(account_id: Current.account.id), fields)
    if params[:q].present?
      query = params[:q].to_s.strip
      raise JrcApprovals::Error, 'INVALID_INPUT' if query.length > 200

      match = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      relation = relation.joins(:policy_version, requester: :user).where(
        "jrc_approvals_policy_versions.publication ->> 'name' ILIKE :match OR users.name ILIKE :match OR " \
        'jrc_approvals_requests.id::text = :query OR jrc_approvals_requests.resource_id::text = :query', match: match, query: query
      )
    end
    case params[:order].presence
    when nil then relation.order(:id)
    when 'recent' then relation.order(created_at: :desc, id: :desc)
    when 'oldest' then relation.order(created_at: :asc, id: :asc)
    else raise JrcApprovals::Error, 'INVALID_INPUT'
    end
  end

  def summary_visible?(record)
    JrcApprovals::RequestVisibility.authorize!(account: Current.account, user: Current.user, record: record)
    true
  rescue Pundit::NotAuthorizedError
    false
  end

  def visible_row(record)
    member = JrcApprovals::RequestVisibility.authorize!(account: Current.account, user: Current.user, record: record)
    return if params[:requested_by_me] == 'true' && member.id != record.requester_id

    choices = inbox_choices(record)
    return unless inbox_matches?(record, member, choices)

    request_payload(record)
  rescue Pundit::NotAuthorizedError
    nil
  end

  def inbox_choices(record)
    return [] unless params[:assigned_to_me] == 'true' || params[:mine] == 'true'

    JrcApprovals::DecisionOptions.call(account: Current.account, user: Current.user, record: record)
  end

  def inbox_matches?(record, member, choices)
    return false if params[:assigned_to_me] == 'true' && choices.empty?

    params[:mine] != 'true' || mine_matches?(record, member, choices)
  end

  def mine_matches?(record, member, choices)
    member.id == record.requester_id || choices.any? || record.stage_plan.any? { |step| step['principal_ids'].include?(member.id) }
  end

  def add_selection_details(item)
    version = JrcApprovals::PolicyVersion.where(account_id: Current.account.id).find(item[:id])
    item[:priority] = version.definition['selection']['priority']
    item[:selection_mode] = version.definition['selection']['mode']
    item[:policy_name] = version.policy.name
    item[:plan].each { |step| step['principal_names'] = simulated_principal_names(step.fetch('principal_ids')) }
  end

  def simulated_principal_names(ids)
    Current.account.account_users.joins(:user).where(id: ids).order('account_users.id').pluck('users.name')
  end
end

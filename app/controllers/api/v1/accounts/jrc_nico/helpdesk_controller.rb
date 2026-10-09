class Api::V1::Accounts::JrcNico::HelpdeskController < Api::V1::Accounts::BaseController
  before_action :helpdesk_context
  rescue_from Pundit::NotAuthorizedError, with: :forbidden
  rescue_from ArgumentError, KeyError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, with: :invalid
  rescue_from JrcNico::OperatorSession::Busy, with: :busy
  rescue_from JrcBroker::Client::Error, with: :unavailable
  rescue_from JrcServiceDesk::LifecycleDependencyError, with: :unavailable

  def show
    policies = JrcNico::Helpdesk::PolicyVersion.where(account: @context.account).order(number: :desc).limit(20)
    render json: { account_id: @context.account.id, catalog: JrcNico::Helpdesk::Catalog.call, policies: policies.map do |policy|
      policy_snapshot(policy)
    end,
                   defaults: @context.native.administrator? ? JrcNico::Helpdesk::Definition.defaults : nil,
                   options: @context.native.administrator? ? configuration_options : {},
                   can_manage: @context.native.administrator?, activation_available: false,
                   external_channels: { email: 'daily_authenticated_pointer_requires_confirmed_recipient',
                                        whatsapp: 'pending_verified_operator_contact_inbox' } }
  end

  def catalog
    render json: { catalog: JrcNico::Helpdesk::Catalog.call }
  end

  def create_policy
    value = params.permit(definition: {}).fetch(:definition).to_h
    policy = JrcNico::Helpdesk::Policies.new(@context.member).create(definition: value)
    render json: policy_snapshot(policy), status: :created
  end

  def publish_policy
    policy = JrcNico::Helpdesk::Policies.new(@context.member).publish(id: params.require(:id), digest: params.require(:digest))
    render json: policy_snapshot(policy)
  end

  def disable_policy
    event = JrcNico::Helpdesk::Controls.new(@context.member).disable(id: params.require(:id), reason: params.require(:reason),
                                                                     request_key: params.require(:request_key))
    render json: event.attributes.slice('id', 'policy_version_id', 'actor_id', 'action', 'reason', 'occurred_at')
  end

  def simulate
    @context.administrator!
    policy = @context.policy(params.require(:policy_id))
    ticket = @context.ticket(params.require(:ticket_id))
    @context.validate_definition_scope!(policy.definition)
    facts = JrcNico::Helpdesk::Facts.new(context: @context, policy: policy, ticket: ticket, trigger: params.require(:trigger)).call
    raise ArgumentError, 'Invalid simulation trigger' unless JrcNico::Helpdesk::Capture::TRIGGERS.include?(params[:trigger])

    render json: { decisions: JrcNico::Helpdesk::RuleDetector.new(definition: policy.definition, facts: facts).call,
                   persisted: false, automatic_execution: false }
  end

  def profile
    attributes = params.permit(:defect_key, :case_kind, :negative_return, :last_relevant_at, customer_note_ids: []).to_h
    value = JrcNico::Helpdesk::ProfileWriter.new(@context.member).call(ticket_id: params.require(:ticket_id), attributes: attributes)
    render json: value.attributes.slice('ticket_id', 'company_id', 'unit_id', 'case_kind', 'defect_key', 'last_relevant_at', 'evidence')
  end

  def events
    values = JrcNico::Helpdesk::Event.where(account: @context.account, ticket_id: @context.tickets.select(:id)).order(id: :desc).limit(100)
    render json: { events: values.filter_map { |event| event_snapshot(event) } }
  end

  def approvals
    values = JrcNico::Helpdesk::Approval.where(account: @context.account, approver: @context.member).order(id: :desc).limit(100)
    render json: { approvals: values.filter_map { |approval| approval_snapshot(approval) } }
  end

  def prepare_approval
    input = params.permit(:event_id, :tool, arguments: {}).to_h
    approval = approval_service.prepare(event_id: input.fetch('event_id'), tool: input.fetch('tool'), arguments: input.fetch('arguments'))
    render json: approval_snapshot(approval), status: :created
  end

  def group_preview
    event = @context.event(params.require(:event_id))
    result = JrcNico::Helpdesk::GroupActionPreview.new(context: @context, event: event,
                                                       group_key: params.require(:group_key), input: group_input).call
    render json: result
  end

  def group_prepare
    arguments = params.require(:arguments).permit!.to_h
    value = approval_service.prepare(event_id: params.require(:event_id), group_key: params.require(:group_key),
                                     input: group_input, tool: params.require(:tool), arguments: arguments,
                                     preview_digest: params.require(:preview_digest))
    render json: approval_snapshot(value), status: :created
  end

  def approve
    render json: approval_snapshot(approval_service.approve(id: params.require(:id), payload_digest: params.require(:payload_digest)))
  end

  def cancel
    render json: approval_snapshot(approval_service.cancel(id: params.require(:id)))
  end

  def reconcile
    approval = approval_service.reconcile(id: params.require(:id), resource_type: params.require(:resource_type),
                                          resource_id: params.require(:resource_id).to_i)
    render json: approval_snapshot(approval)
  end

  def report
    policy = @context.policy(params.require(:policy_id))
    render json: JrcNico::Helpdesk::DailyReporter.new(policy, filters: report_scope_params).preview(member: @context.member)
  end

  def kpis
    policy = @context.policy(params.require(:policy_id))
    from = Time.iso8601(params.require(:from))
    until_at = params[:until].present? ? Time.iso8601(params[:until]) : Time.current
    render json: JrcNico::Helpdesk::Kpis.new(member: @context.member, policy: policy, from: from,
                                             until_at: until_at, filters: report_scope_params).call
  end

  def reports
    render json: JrcNico::Helpdesk::ReportHistory.new(@context.member).collection(policy_id: params.require(:policy_id), page: params.fetch(:page, 1))
  end

  def report_history
    render json: JrcNico::Helpdesk::ReportHistory.new(@context.member).find(params.require(:id))
  end

  def broker_health
    binding = JrcBrokerInboxBinding.where(account: @context.account).find(params.require(:binding_id))
    render json: JrcNico::Helpdesk::BrokerHealth.new(@context.member).call(binding: binding)
  end

  private

  def report_scope_params
    return {} unless params.key?(:filters)

    value = params[:filters]
    valid = value.is_a?(ActionController::Parameters) || value.is_a?(Hash)
    raise ArgumentError, 'Explicit report filter object required' unless valid
    raise ArgumentError, 'Unsupported reporting filters' unless (value.keys.map(&:to_s) - JrcNico::Helpdesk::ReportingScope::KEYS).empty?

    result = {}
    value.each_pair do |key, ids|
      raise ArgumentError, 'Explicit bounded report filter arrays required' unless ids.is_a?(Array) && ids.size <= 1000

      parsed = ids.map { |id| JrcServiceDesk::Input.id(id) }
      JrcNico::Helpdesk::Definition.ids!(parsed)
      result[key.to_s] = parsed
    end
    result
  end

  def helpdesk_context
    @context = JrcNico::Helpdesk::Context.new(Current.account_user)
    raise Pundit::NotAuthorizedError unless @context.account.id == Current.account.id
  end

  def approval_service
    JrcNico::Helpdesk::Approvals.new(@context.member)
  end

  def group_input
    value = params[:input]
    value ? value.permit!.to_h : {}
  end

  def policy_snapshot(policy)
    fields = %w[id number state enabled digest published_at created_at]
    fields << 'definition' if @context.native.administrator?
    policy.attributes.slice(*fields).merge('enabled' => policy.enabled?,
                                           'halted' => JrcNico::Helpdesk::PolicyControl.exists?(
                                             policy_version: policy, halted: true
                                           ))
  end

  def configuration_options
    units = @context.native.view_unit_scope.order(:name).to_a
    { units: units.map { |unit| { id: unit.id, name: unit.name } }, companies: authorized_companies,
      operators: @context.account.account_users.includes(:user).map { |member| { id: member.id, name: member.user.name } },
      priorities: JrcServiceDesk::Priority.where(account: @context.account, unit_id: units.map(&:id), active: true).order(:position, :id)
                                          .map { |priority| { id: priority.id, unit_id: priority.unit_id, name: priority.name } } }
  end

  def authorized_companies
    return [] unless JrcCustomers::DirectoryPolicy.new(@context.native.to_h, :directory).access?

    JrcCustomers::Company.where(account: @context.account).order(:name).limit(1000).pluck(:id, :name)
                         .map { |id, name| { id: id, name: name } }
  end

  def event_snapshot(event)
    @context.event(event.id)
    event.attributes.slice('id', 'ticket_id', 'rule_key', 'state', 'reason', 'evidence', 'result', 'detected_at', 'completed_at')
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    nil
  end

  def approval_snapshot(approval)
    @context.event(approval.event_id)
    if approval.scope['group']
      JrcNico::Helpdesk::GroupActionPreview.authorize_saved_sources!(@context, approval.scope['group'], event: approval.event)
    end
    draft_resources = if approval.scope['group']
                        JrcNico::Helpdesk::GroupNativeActions.authorize_result!(@context, approval)
                      end
    JrcNico::Notice.resources_for(approval.command).each do |type, id|
      next if Array(draft_resources).include?([type, id])

      JrcNico::Helpdesk::GroupNativeActions.authorize_resource!(@context, type, id)
    end
    approval.attributes.slice('id', 'event_id', 'state', 'payload_digest', 'scope', 'expires_at', 'approved_at', 'reconciliation')
            .merge('tool' => approval.command.tool, 'arguments' => approval.command.arguments)
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    nil
  end

  def forbidden
    render json: { error: 'HELPDESK_ACCESS_DENIED' }, status: :forbidden
  end

  def invalid
    render json: { error: 'HELPDESK_INVALID_REQUEST' }, status: :unprocessable_entity
  end

  def busy
    render json: { error: 'HELPDESK_BUSY' }, status: :conflict
  end

  def unavailable
    render json: { error: 'HELPDESK_PROVIDER_UNAVAILABLE' }, status: :service_unavailable
  end
end

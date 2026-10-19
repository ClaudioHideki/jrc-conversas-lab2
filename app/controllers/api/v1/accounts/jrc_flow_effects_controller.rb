class Api::V1::Accounts::JrcFlowEffectsController < Api::V1::Accounts::BaseController
  before_action :require_service_user
  rescue_from ArgumentError, ActiveRecord::RecordNotUnique, with: :invalid_request
  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  def capabilities
    authority = service_authority.authorize!
    inbox = authority.account.inboxes.find(JrcFlowEffects::Request.integer(params[:inbox_id]))
    supported = JrcFlowEffects::ControlRevision.available?
    render json: { protocol: JrcFlowEffects::Request::PROTOCOL, account_id: authority.account.id, inbox_id: inbox.id,
                   control_revision_supported: supported, operations: supported ? %w[tag attribute note resolve] : [],
                   resources: supported ? JrcFlowEffects::Resources.catalogue(authority.account) : [] }
  end

  def context
    raise ArgumentError, 'control_unavailable' unless JrcFlowEffects::ControlRevision.available?

    snapshot = Conversation.transaction do
      authority = service_authority.authorize!(lock: true)
      conversation = authority.account.conversations.lock.find_by!(display_id: JrcFlowEffects::Request.integer(params[:conversation_id]))
      state = JrcFlowEffects::ControlRevision.snapshot(conversation)
      state['conversation_id'] = state.delete('remote_conversation_id')
      state.merge('protocol' => JrcFlowEffects::Request::PROTOCOL, 'actor_user_id' => authority.user.id,
                  'status' => conversation.status, 'assignee_id' => conversation.assignee_id,
                  'assignee_agent_bot_id' => conversation.assignee_agent_bot_id, 'team_id' => conversation.team_id)
    end
    render json: snapshot
  end

  def show
    validate_receipt_identity!

    receipt = Conversation.transaction do
      authority = service_authority.authorize!(lock: true)
      conversation = authority.account.conversations.find_by!(display_id: JrcFlowEffects::Request.integer(params[:conversation_id]))
      row = JrcFlowEffectReceipt.find_by!(account_id: authority.account.id, conversation_id: conversation.id,
                                          organization_id: params[:organization_id], operation_id: params[:operation_id])
      raise ArgumentError, 'domain_endpoint_required' if row.operation == 'domain'
      row.verify!(conversation: conversation, user: authority.user, proof: params[:dispatch_proof], request_hash: row.request_hash)
    end
    render json: receipt.protocol_receipt
  end

  def create
    raise ArgumentError, 'request_bound' if request.raw_post.bytesize > 16_384

    input = params.permit(*JrcFlowEffects::Request::KEYS).to_h
    raise ArgumentError, 'domain_endpoint_required' if input['operation'] == 'domain'
    receipt = JrcFlowEffects::Apply.new(account: Current.account, user: @resource, access_token: @access_token)
                                   .call(params[:conversation_id], input)
    render json: receipt.protocol_receipt
  end

  private

  def validate_receipt_identity!
    keys = %i[organization_id operation_id dispatch_proof]
    raise ArgumentError, 'identity' unless keys.all? { |key| JrcFlowEffects::Request::UUID.match?(params[key].to_s) }
  end

  def service_authority
    JrcFlowEffects::Authority.new(account: Current.account, user: @resource, access_token: @access_token)
  end

  def require_service_user
    response.headers['Cache-Control'] = 'no-store'
    raise Pundit::NotAuthorizedError unless authenticate_by_access_token? && @resource.is_a?(User)
  end

  def invalid_request
    render json: { error: 'JRC_EFFECT_REQUEST_INVALID' }, status: :conflict
  end

  def not_found
    render json: { error: 'JRC_EFFECT_SCOPE_NOT_FOUND' }, status: :not_found
  end
end

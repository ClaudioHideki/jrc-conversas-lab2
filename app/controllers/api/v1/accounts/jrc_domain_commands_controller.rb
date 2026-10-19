class Api::V1::Accounts::JrcDomainCommandsController < Api::V1::Accounts::JrcFlowEffectsController
  wrap_parameters false

  def capabilities
    value = Conversation.transaction do
      authority = service_authority.authorize!(lock: true)
      scope = JrcDomainCommands::Scope.new(authority)
      inbox = scope.authorize!(params.permit(:inbox_id, :organization_id, :integration_id).to_h)
      supported = JrcDomainCommands::Request.available?
      { protocol: JrcDomainCommands::Request::PROTOCOL, account_id: authority.account.id, inbox_id: inbox.id,
        organization_id: params[:organization_id], integration_id: params[:integration_id],
        commands: supported ? JrcDomainCommands::Request::COMMANDS : [], owners: supported ? scope.owners : [] }
    end
    render json: value
  end

  def show
    validate_receipt_identity!
    receipt = Conversation.transaction { domain_receipt(service_authority.authorize!(lock: true)) }
    render json: receipt.protocol_receipt
  end

  def create
    receipt = JrcFlowEffects::Apply.new(account: Current.account, user: @resource, access_token: @access_token)
                                   .call(params[:conversation_id], domain_input)
    render json: receipt.protocol_receipt
  end

  private

  def domain_input
    allowed = JrcFlowEffects::Request::KEYS - %w[resource_id resource_revision]
    valid = request.raw_post.bytesize <= 16_384 && request.request_parameters.keys.sort == allowed.sort && request.query_parameters.empty?
    raise ArgumentError, 'domain_request' unless valid

    input = params.permit(*allowed).to_h
    raise ArgumentError, 'domain_operation' unless input['operation'] == 'domain'

    input
  end

  def domain_conversation(authority)
    scope_input = params.permit(:organization_id, :integration_id).to_h.merge('inbox_id' => params.fetch(:inbox_id).to_s)
    JrcDomainCommands::Scope.new(authority).authorize!(scope_input)
    authority.account.conversations.find_by!(display_id: JrcFlowEffects::Request.integer(params[:conversation_id]))
  end

  def domain_receipt(authority)
    conversation = domain_conversation(authority)
    row = JrcFlowEffectReceipt.find_by!(account_id: authority.account.id, conversation_id: conversation.id, operation: 'domain',
                                        organization_id: params[:organization_id], operation_id: params[:operation_id])
    raise ArgumentError, 'domain_inbox' unless row.inbox_id == JrcFlowEffects::Request.integer(params[:inbox_id])

    row.verify!(conversation: conversation, user: authority.user, proof: params[:dispatch_proof], request_hash: row.request_hash)
  end
end

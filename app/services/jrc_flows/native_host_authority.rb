class JrcFlows::NativeHostAuthority
  def initialize(account_id:, user_id:)
    @account_id = account_id
    @user_id = user_id
  end

  def administrator!
    Account.transaction do
      account = Account.lock('FOR SHARE').find_by(id: @account_id)
      fail!('FLOW_ACCOUNT_INACTIVE') unless account&.active?
      fail!('FLOW_FEATURE_DISABLED') unless JrcFlows::Access.enabled?(account)
      member = AccountUser.lock('FOR SHARE').find_by(account_id: @account_id, user_id: @user_id)
      fail!('FLOW_MEMBERSHIP_REQUIRED') unless member
      permissions = member.permissions
      unless member.custom_role_id.nil? && permissions.include?('administrator') && !permissions.include?('custom_role')
        fail!('FLOW_CAPABILITY_NOT_GRANTED')
      end
      member
    end
  end

  def authorize!(record:, inbox_ids:, scopes:, nonce:)
    context = { account_id: @account_id, organization_id: record.organization_id, origin: record.host_origin,
                destination_revision: record.destination_revision }
    request = { 'nonce' => nonce, 'externalActorId' => @user_id.to_s, 'accountId' => @account_id,
                'destinationRevision' => record.destination_revision, 'inboxIds' => inbox_ids }
    introspection = JrcFlows::NativeIntrospection.new(context_resolver: -> { context })
    scopes.each { |scope| introspection.authorize!(request, scope: scope) }
  end

  private

  def fail!(code)
    raise JrcFlows::NativeClient::Error.new(code, status: 403)
  end
end

class JrcDomainCommands::Scope
  def initialize(authority)
    @authority = authority
    @account = authority.account
  end

  def authorize!(input)
    authorize_actor!
    validate_identity!(input)
    binding = binding!(input)
    @account.inboxes.lock('FOR SHARE').find(binding.inbox_id)
  end

  def owners
    members = @account.account_users.includes(:user).order(:id).limit(201).to_a
    raise ArgumentError, 'domain_owner_directory_bound' if members.size > 200

    members.filter_map do |member|
      next unless JrcOperations::Access.crm?(member) && member.user.active_for_authentication? && member.user.confirmed?

      { id: member.user_id, name: member.user.name.to_s.first(160) }
    end
  end

  private

  def authorize_actor!
    raise Pundit::NotAuthorizedError unless JrcBroker::Configuration.enabled? && @account.feature_enabled?('jrc_broker')

    member = @account.account_users.lock('FOR SHARE').find_by!(user_id: @authority.user.id)
    CustomRole.lock('FOR SHARE').find(member.custom_role_id) if member.custom_role_id
    raise Pundit::NotAuthorizedError unless JrcOperations::Access.crm?(member)
  end

  def validate_identity!(input)
    valid = %w[organization_id integration_id].all? { |key| JrcFlowEffects::Request::UUID.match?(input[key].to_s) }
    raise ArgumentError, 'domain_identity' unless valid
  end

  def binding!(input)
    integration = JrcBrokerIntegration.lock('FOR SHARE').find_by!(account_id: @account.id)
    binding = JrcBrokerInboxBinding.lock('FOR SHARE').find_by!(account_id: @account.id,
                                                               inbox_id: JrcFlowEffects::Request.integer(input['inbox_id']))
    unless integration.organization_id == input.fetch('organization_id') && binding.integration_id == input.fetch('integration_id')
      raise ArgumentError, 'domain_binding'
    end

    binding
  end
end

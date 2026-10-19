class JrcDomainCommands::ResourceScope
  def initialize(account:, user:)
    @account = account
    @user = user
    @member = account.account_users.lock('FOR SHARE').find_by!(user_id: user.id)
    CustomRole.lock('FOR SHARE').find(@member.custom_role_id) if @member.custom_role_id
    JrcCrm::UserBusinessUnit.where(account: account, user: user).order(:id).lock('FOR SHARE').load
    account.jrc_crm_business_units.order(:id).lock('FOR SHARE').load
    account.master_companies.where(relationship_type: 'internal').order(:id).lock('FOR SHARE').load
    raise Pundit::NotAuthorizedError unless JrcOperations::Access.crm?(@member)
  end

  def authorize!(record)
    relation = record.class.where(account_id: @account.id, id: record.id)
    column = record.is_a?(JrcCrm::Activity) ? :user_id : :owner_id
    relation = relation.where(column => @user.id) unless @member.administrator?
    raise Pundit::NotAuthorizedError unless visible(relation).exists?

    record
  end

  def new_lead_unit
    boundary = JrcCrm::OrganizationalVisibility.new(account: @account, user: @user, relation: @account.jrc_crm_leads)
    ids = boundary.allowed_business_unit_ids
    return if ids.nil?

    # A conversation does not identify an issuer. Never pick an arbitrary unit.
    units = @account.jrc_crm_business_units.where(id: ids, active: true).limit(2).to_a
    raise ArgumentError, 'domain_business_unit_ambiguous' unless units.one?

    units.first.id
  end

  def authorize_result!(result)
    relation = case result.fetch('resource_type')
               when 'JrcCrm::Lead' then @account.jrc_crm_leads
               when 'JrcCrm::Activity' then @account.jrc_crm_activities
               else raise ArgumentError, 'domain_resource'
               end
    record = relation.lock('FOR SHARE').find(result.fetch('resource_id'))
    authorize!(record)
    authorize!(record.lead) if record.is_a?(JrcCrm::Activity) && record.lead
  end

  private

  def visible(relation)
    JrcCrm::OrganizationalVisibility.new(account: @account, user: @user, relation: relation).call
  end
end

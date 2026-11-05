# Current native configuration and destination authority, not client-supplied scope.
class JrcRelationship::DistributionPolicyBinding
  def initialize(context)
    @context = context
  end

  def call(records, owner_id: nil)
    configurations = records.map do |row|
      config = @context.configuration(row)
      { 'assignment_id' => row.id, 'scope_key' => config.scope_key, 'version' => config.version,
        'required' => config.effective_rules.fetch('portfolio_transfer_approval_required') }
    end
    corporate_scope(records).merge('required' => configurations.any? { |row| row.fetch('required') },
                                   'configurations' => configurations,
                                   'destination_access_signature' => destination_signature(records, owner_id))
  end

  private

  def corporate_scope(records)
    units = JrcCrm::BusinessUnit.where(account_id: @context.account.id, id: records.map(&:business_unit_id)).index_by(&:id)
    scopes = records.map { |row| [units[row.business_unit_id]&.company_id, row.business_unit_id] }.uniq
    companies = scopes.map(&:first).uniq
    { 'issuer_company_id' => companies.one? ? companies.first : nil, 'business_unit_id' => scopes.one? ? scopes.first.last : nil }
  end

  def destination_signature(records, owner_id)
    return unless owner_id

    user = @context.assignable_users.lock('FOR SHARE').find(owner_id)
    raise Pundit::NotAuthorizedError unless user.active_for_authentication?

    destination = lock_destination(user)
    scope = JrcRelationship::Assignment.where(account_id: @context.account.id, id: records.map(&:id))
    covered = JrcCrm::OrganizationalVisibility.new(account: @context.account, user: user, relation: scope, include_company: false).call
    raise Pundit::NotAuthorizedError unless covered.count == records.size

    destination.access_signature
  end

  def lock_destination(user)
    member = @context.account.account_users.lock('FOR SHARE').find_by!(user_id: user.id)
    CustomRole.lock('FOR SHARE').find(member.custom_role_id) if member.custom_role_id
    JrcCrm::UserBusinessUnit.where(account_id: @context.account.id, user_id: user.id).order(:id).lock('FOR SHARE').load
    TeamMember.where(team_id: @context.account.teams.select(:id), user_id: user.id).order(:id).lock('FOR SHARE').load
    JrcRelationship::Context.new(member)
  end
end

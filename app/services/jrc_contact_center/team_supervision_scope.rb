# frozen_string_literal: true

# A supervisor selection never creates coverage: every native active TeamScope must already be covered.
class JrcContactCenter::TeamSupervisionScope
  def initialize(account:, team:, member:)
    @account = account
    @team = team
    @member = member
  end

  def covered?
    return false unless @team.account_id == @account.id && @member.account_id == @account.id

    requirements = JrcCrm::TeamScope.active.where(account: @account, team: @team).includes(:company, :business_unit, :team).to_a
    return false unless requirements.all? { |requirement| valid_requirement?(requirement) }
    return true if sources.exists?(scope: 'GROUP')

    if requirements.empty?
      return !JrcContactCenter::CorporateCoverage.new(account: @account, user: @member.user).configured?
    end

    requirements.all? { |requirement| covered_requirement?(requirement) }
  end

  private

  def sources
    projection = JrcContactCenter::TeamSourceProjection.new(account: @account)
    JrcCrm::CurrentStructureScopes.new(account: @account, user: @member.user, team_membership_projection: projection).call
  end

  def valid_requirement?(requirement)
    return false unless requirement.valid?
    return true unless requirement.scope == 'BUSINESS_UNIT' && requirement.business_unit.company_id

    company = @account.master_companies.find_by(id: requirement.business_unit.company_id, relationship_type: 'internal')
    company && (!company.respond_to?(:active?) || company.active?)
  end

  def covered_requirement?(requirement)
    case requirement.scope
    when 'COMPANY'
      sources.exists?(scope: 'COMPANY', company_id: requirement.company_id)
    when 'BUSINESS_UNIT'
      sources.exists?(scope: 'BUSINESS_UNIT', business_unit_id: requirement.business_unit_id) ||
        company_source?(requirement.business_unit.company_id)
    else
      false
    end
  end

  def company_source?(id)
    id.present? && sources.exists?(scope: 'COMPANY', company_id: id)
  end
end

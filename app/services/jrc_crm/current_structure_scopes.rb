# Current sources of an explicit corporate grant; joining a team creates no grant.
class JrcCrm::CurrentStructureScopes
  def initialize(account:, user:)
    @account = account
    @user = user
  end

  def call
    relation = @account.jrc_crm_user_business_units.structure_managed.active.where(user_id: @user&.id)
    direct = relation.where(team_id: nil)
    inherited = relation.where(team_id: current_team_ids).where(containing_team_scope)
    direct.or(inherited)
  end

  private

  def current_team_ids
    Team.where(account_id: @account.id).joins(:team_members)
        .where(team_members: { user_id: @user&.id }).select(:id)
  end

  def containing_team_scope
    scopes = JrcCrm::TeamScope.active.where(account_id: @account.id)
    scopes.where('jrc_crm_team_scopes.team_id = jrc_crm_user_business_units.team_id').where(containment_sql).arel.exists
  end

  def containment_sql
    <<~SQL.squish
      (jrc_crm_team_scopes.scope = 'GROUP'
      OR (jrc_crm_team_scopes.scope = 'COMPANY'
        AND jrc_crm_user_business_units.scope IN ('COMPANY', 'BUSINESS_UNIT')
        AND jrc_crm_team_scopes.company_id = CASE WHEN jrc_crm_user_business_units.scope = 'BUSINESS_UNIT' THEN
          (SELECT covered_unit.company_id FROM jrc_crm_business_units covered_unit
           WHERE covered_unit.id = jrc_crm_user_business_units.business_unit_id
             AND covered_unit.account_id = jrc_crm_user_business_units.account_id)
          ELSE jrc_crm_user_business_units.company_id END)
      OR (jrc_crm_team_scopes.scope = 'BUSINESS_UNIT'
        AND jrc_crm_user_business_units.scope = 'BUSINESS_UNIT'
        AND jrc_crm_team_scopes.business_unit_id = jrc_crm_user_business_units.business_unit_id))
    SQL
  end
end

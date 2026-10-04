module JrcCrm
  class OrganizationalStructureService
    SETTINGS_KEY = 'jrc_crm_organization'.freeze

    def initialize(account:, actor:)
      @account = account
      @actor = actor
    end

    def snapshot
      {
        group: group_payload,
        operating_companies: company_payload,
        business_units: business_unit_payload,
        teams: team_payload,
        users: user_payload,
        team_scopes: team_scope_payload,
        user_scopes: user_scope_payload,
        legacy_user_scope_count: account.jrc_crm_user_business_units.where(structure_managed: false).count,
        permissions_source: 'native_roles_and_custom_roles'
      }
    end

    def update_settings!(attributes)
      current = organization_settings
      allowed = attributes.to_h.symbolize_keys.slice(:group_name, :scope_enforcement_enabled)
      allowed[:group_name] = allowed[:group_name].to_s.strip.presence || account.name if allowed.key?(:group_name)
      allowed[:scope_enforcement_enabled] = ActiveModel::Type::Boolean.new.cast(allowed[:scope_enforcement_enabled]) if allowed.key?(:scope_enforcement_enabled)
      account.update!(custom_attributes: account.custom_attributes.merge(SETTINGS_KEY => current.merge(allowed.stringify_keys)))
      group_payload
    end

    private

    attr_reader :account, :actor

    def organization_settings
      value = account.custom_attributes.fetch(SETTINGS_KEY, {})
      value.is_a?(Hash) ? value : {}
    end

    def group_payload
      settings = organization_settings
      {
        id: account.id,
        name: settings['group_name'].presence || account.name,
        scope_enforcement_enabled: ActiveModel::Type::Boolean.new.cast(settings['scope_enforcement_enabled']),
        account_name: account.name
      }
    end

    def company_payload
      internal_companies.map do |company|
        {
          id: company.id,
          name: company.name,
          trade_name: company.try(:trade_name),
          segment: company.try(:segment),
          active: company.try(:active) != false,
          relationship_type: company.try(:relationship_type),
          revision: company.updated_at&.iso8601(6)
        }
      end
    end

    def internal_companies
      @internal_companies ||= account.master_companies.where(relationship_type: 'internal').order(:name, :id).to_a
    end

    def business_unit_payload
      account.jrc_crm_business_units.includes(:operating_company).order(:name, :id).map do |unit|
        {
          id: unit.id,
          name: unit.name,
          code: unit.code,
          segment: unit.segment,
          active: unit.active,
          company_id: unit.company_id,
          company_name: unit.operating_company&.name,
          legacy_unassigned: unit.company_id.nil?,
          settings: unit.settings
        }
      end
    end

    def team_payload
      account.teams.includes(:members).order(:name, :id).map do |team|
        {
          id: team.id,
          name: team.name,
          description: team.description,
          members: team.members.map { |user| { id: user.id, name: user.name, email: user.email } },
          members_count: team.members.size
        }
      end
    end

    def user_payload
      memberships = AccountUser.where(account_id: account.id).includes(:user).order(:id)
      team_ids_by_user = TeamMember.joins(:team).where(teams: { account_id: account.id }).group_by(&:user_id)
      memberships.map do |membership|
        {
          id: membership.user_id,
          account_user_id: membership.id,
          name: membership.user.name,
          email: membership.user.email,
          role: membership.role,
          crm_enabled: membership.crm_enabled,
          team_ids: Array(team_ids_by_user[membership.user_id]).map(&:team_id).uniq.sort
        }
      end
    end

    def team_scope_payload
      account.jrc_crm_team_scopes.includes(:team, :company, :business_unit).order(:team_id, :id).map do |record|
        serialize_scope(record).merge(team_name: record.team.name)
      end
    end

    def user_scope_payload
      account.jrc_crm_user_business_units.structure_managed.includes(:user, :team, :company, :business_unit).order(:user_id, :team_id, :id).map do |record|
        serialize_scope(record).merge(user_id: record.user_id, user_name: record.user.name, team_name: record.team&.name)
      end
    end

    def serialize_scope(record)
      {
        id: record.id,
        scope: record.scope,
        team_id: record.team_id,
        company_id: record.company_id,
        company_name: record.company&.name,
        business_unit_id: record.business_unit_id,
        business_unit_name: record.business_unit&.name,
        active: record.active
      }
    end
  end
end

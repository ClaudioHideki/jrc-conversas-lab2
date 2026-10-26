# frozen_string_literal: true

# Model grants intersect, never replace, native module/source/unit permissions.
class JrcRelationship::SurveyModelAccess
  attr_reader :context, :operational
  def initialize(context)
    @context = context
    @operational = JrcServiceDesk::OperationalContext.new(context.to_h)
  end

  def units
    return JrcServiceDesk::Unit.none unless context.policy.access? && operational.capability?(:tickets_view)
    operational.view_unit_scope
  end

  def unit!(id)
    units.find(id)
  end

  def role
    return 'administrator' if context.policy.admin?
    context.policy.team? ? 'supervisor' : 'agent'
  end

  def allowed?(payload, action)
    return false unless payload.is_a?(Hash) && units.exists?(id: payload['unit_id'])
    return allowed?(payload, 'edit') || allowed?(payload, 'publish') if action == 'read'

    return false if %w[edit publish].include?(action) && !context.policy.configure?
    return true if context.policy.admin?

    permissions = payload['permissions'] || {}
    teams = Array(permissions['team_ids'])
    team_ok = teams.empty? || TeamMember.where(user_id: context.user.id, team_id: context.account.teams.where(id: teams).select(:id)).exists?
    team_ok && Array(permissions["#{action}_roles"]).include?(role)
  end

  def authorize!(draft, action)
    unit!(draft.unit_id)
    policy = draft.published_payload.presence || draft.payload
    raise Pundit::NotAuthorizedError unless draft.account_id == context.account.id && allowed?(policy, action)
  end

  def create?
    context.policy.admin? && context.policy.configure? && units.exists?
  end

  def self.visible_scope(context, rows, action: 'response', share: nil)
    raise ArgumentError, 'Unknown survey grant' unless %w[response report].include?(action)
    raise ArgumentError, 'Unknown sharing grant' unless [nil, 'share_relationship', 'share_reports'].include?(share)
    access = new(context)
    column = 'jrc_relationship_surveys.definition_snapshot'
    native = rows.where("NOT COALESCE(jsonb_exists(#{column}->'settings', 'service_desk_model'), false)")
    data = "#{column}->'settings'->'service_desk_model'"
    v3 = rows.where("#{data}->>'unit_id' IN (?)", access.units.pluck(:id).map(&:to_s))
    unless context.policy.admin?
      v3 = v3.where("jsonb_exists(#{data}->'permissions'->?, ?)", "#{action}_roles", access.role)
      teams = context.account.teams.where(id: TeamMember.where(user_id: context.user.id).select(:team_id)).pluck(:id).map(&:to_s)
      v3 = v3.where("#{data}->'permissions'->'team_ids' = '[]'::jsonb OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(#{data}->'permissions'->'team_ids') AS team(value) WHERE team.value IN (?))", teams.presence || ['-1'])
    end
    v3 = v3.where("#{data}->'permissions'->>? = 'true'", share) if share
    current = JrcRelationship::SurveyDefinition.where(account: context.account)
    current_data = "settings->'service_desk_model'"
    unless context.policy.admin?
      current = current.where("jsonb_exists(#{current_data}->'permissions'->?, ?)", "#{action}_roles", access.role)
      current = current.where("#{current_data}->'permissions'->'team_ids' = '[]'::jsonb OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(#{current_data}->'permissions'->'team_ids') AS t(value) WHERE t.value IN (?))", teams.presence || ['-1'])
    end
    current = current.where("#{current_data}->'permissions'->>? = 'true'", share) if share
    native.or(v3.where(definition_id: current.select(:id)))
  end
end

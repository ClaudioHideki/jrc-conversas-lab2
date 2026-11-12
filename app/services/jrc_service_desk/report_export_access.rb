# frozen_string_literal: true

# Both the worker and authenticated download refresh the native identity and
# intersect the same report scope. A ready blob is never a bearer/public link.
class JrcServiceDesk::ReportExportAccess
  attr_reader :query

  def initialize(export, user_context)
    @export = export
    @query = JrcServiceDesk::OperationalReportQuery.new(user_context: user_context, parameters: export.filters, permission: 'reports_export')
    unless query.context.account.id == export.account_id && query.context.account_user.id == export.account_user_id && query.unit.id == export.unit_id
      raise Pundit::NotAuthorizedError
    end
  end

  def signature
    context = query.context
    permissions = %w[reports_export customers_view history_view sla_view conversations_view]
    identities = permissions.to_h do |permission|
      rows = query.relation_for(permission).reorder(:id).pluck(:id)
      [permission, Digest::SHA256.hexdigest(rows.join(','))]
    end
    member = context.account_user
    role = member.respond_to?(:custom_role) ? member.custom_role : nil
    value = { capabilities: context.effective_capabilities.sort, role: member.role, permissions: member.permissions.sort,
              custom_role: role&.attributes, teams: context.native_team_ids.reorder(:id).pluck(:id), rows: identities,
              survey_ids: JrcServiceDesk::ReportSurveyScope.for(query).order(:id).pluck(:id) }
    Digest::SHA256.hexdigest(JrcServiceDesk::CanonicalJson.dump(value))
  end

  def verify!
    raise Pundit::NotAuthorizedError unless @export.authorization_signature == signature
    raise ArgumentError, 'Export expired' if @export.expires_at <= Time.current

    true
  end
end

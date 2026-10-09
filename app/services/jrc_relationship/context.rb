class JrcRelationship::Context
  attr_reader :member, :account, :user

  def initialize(member)
    @member = AccountUser.find_by!(id: member.id, account_id: member.account_id, user_id: member.user_id)
    @account = @member.account
    @user = @member.user
    raise Pundit::NotAuthorizedError unless policy.access?
  end

  def policy
    JrcRelationship::ModulePolicy.new(to_h, account)
  end

  def to_h
    { account: account, user: user, account_user: member }
  end

  def formatting
    { locale: account.locale.to_s.tr('_', '-').presence || 'pt-BR', currency: 'BRL',
      timeZone: (Time.find_zone(account.reporting_timezone) || Time.zone).tzinfo.name }
  end

  def assignments
    JrcRelationship::AssignmentPolicy::Scope.new(to_h, JrcRelationship::Assignment).resolve
  end

  def assignment(id, write: false)
    record = assignments.find(id)
    raise Pundit::NotAuthorizedError if write && !policy.manage?

    record
  end

  def records(model)
    relation = model.where(account_id: account.id, assignment_id: assignments.select(:id))
    relation = JrcRelationship::RecordVisibility.new(self).source_scope(model, relation)
    return relation.none if [JrcRelationship::Renewal, JrcRelationship::ExpansionSignal].include?(model) && !JrcOperations::Access.crm?(member)

    visibility = JrcCustomers::Visibility.new(account: account, user: user, account_user: member)
    if model == JrcRelationship::Renewal
      relation = relation.where(contract_id: visibility.crm(account.jrc_crm_contracts).select(:id))
    elsif model == JrcRelationship::ExpansionSignal
      relation = JrcRelationship::RecordVisibility.new(self).expansions(relation, visibility)
    elsif model == JrcRelationship::SuccessPlan
      relation = relation.where(project_id: nil).or(relation.where(project_id: visibility.projects.select(:id)))
      sources = { 'task_id' => visibility.project_tasks(visibility.projects), 'ticket_id' => visibility.tickets,
        'activity_id' => visibility.crm(account.jrc_crm_activities, owner: :user_id),
        'qbr_id' => JrcRelationship::Qbr.where(account: account, assignment_id: assignments.select(:id)),
        'product_id' => visibility.crm? ? account.jrc_crm_products : account.jrc_crm_products.none }
      sources.each do |key, source_scope|
        sql = source_scope.reselect(source_scope.klass.arel_table[:id]).reorder(nil).to_sql
        relation = relation.where("NOT EXISTS (SELECT 1 FROM jsonb_array_elements(jrc_relationship_success_plans.goals || COALESCE(NULLIF(jrc_relationship_success_plans.metadata -> 'milestones', 'null'::jsonb), '[]'::jsonb)) AS goal(value) " \
          "WHERE NULLIF(goal.value ->> ?, '') IS NOT NULL AND (goal.value ->> ?)::bigint NOT IN (#{sql}))", key, key)
      end
    end
    if model == JrcRelationship::Action
      relation = relation.where.not(kind: %w[finance renewal]) unless visibility.crm?
      relation = relation.where.not(kind: %w[ticket recurring_ticket post_ticket]) unless visibility.service_desk?
    end
    if [JrcRelationship::Action, JrcRelationship::RiskCase].include?(model)
      relation = JrcRelationship::SnapshotAccess.scope(self, relation, column: 'metadata', require_manifest: false)
    end
    relation
  end

  def assignable_users
    return account.users if policy.admin?

    team_ids = account.teams.joins(:team_members).where(team_members: { user_id: user.id }).select(:id)
    account.users.where(id: TeamMember.where(team_id: team_ids).select(:user_id)).or(account.users.where(id: user.id))
  end

  def audit!(record, before: {}, after: {}, action: 'updated')
    assignment_id = if record.is_a?(JrcRelationship::Assignment)
                      record.id
                    else
                      record.try(:assignment_id) || record.try(:metadata)&.dig('relationship_assignment_id')
                    end
    JrcCustomers::Audit.record!(account: account, actor: user, resource: record, event_type: 'relationship_updated',
                                from_value: before, to_value: after,
                                metadata: { action: action, assignment_id: assignment_id })
  end

  def access_signature
    require 'digest'
    @access_signature ||= Digest::SHA256.hexdigest(
      [member.role, member.custom_role_id, member.custom_role&.updated_at,
       member.permissions.sort, account[:feature_flags], account[:feature_flags_ext_1],
       account.custom_attributes[JrcCrm::OrganizationalStructureService::SETTINGS_KEY],
       account.jrc_crm_user_business_units.where(user_id: user.id).maximum(:updated_at),
       TeamMember.where(team_id: account.teams.select(:id), user_id: user.id).order(:id).pluck(:id,
                                                                                               :updated_at),
       JrcServiceDesk::UnitMembership.where(account_id: account.id,
                                            account_user_id: member.id).order(:id).pluck(:id, :updated_at),
       JrcProjects::ProjectMember.where(account_id: account.id,
                                        user_id: user.id).order(:id).pluck(:id, :updated_at),
       InboxMember.where(inbox_id: account.inboxes.select(:id),
                         user_id: user.id).order(:id).pluck(:id, :updated_at)].join(':')
    )
  end

  def configuration(assignment = nil)
    product = assignment&.settings&.dig('product_id')
    configurations = @configurations ||= JrcRelationship::Configuration.where(account_id: account.id).index_by(&:scope_key)
    product_config = configurations["product:#{product}"] if product
    return product_config if product_config

    segment = assignment&.settings&.dig('segment_id')
    key = segment ? "segment:#{segment}" : 'account'
    choices = [configurations[key], customer_configuration(assignment, configurations), configurations['account']]
    choices.compact.first ||
      JrcRelationship::Configuration.new(account: account, scope_key: 'account')
  end

  def customer_configuration(assignment, configurations)
    customer_config = configurations["company:#{assignment.company_id}"] if assignment&.company_id
    unit_config = configurations["unit:#{assignment.business_unit_id}"] if assignment&.business_unit_id
    customer_config || unit_config
  end
  private :customer_configuration

  def authorize_configuration_scope!(scope_key)
    raise Pundit::NotAuthorizedError unless policy.configure?

    kind, id = scope_key.to_s.split(':')
    return if policy.admin?

    case kind
    when 'company' then assignments.find_by!(company_id: id)
    when 'unit' then assignments.find_by!(business_unit_id: id)
    when 'segment', 'product'
      raise Pundit::NotAuthorizedError unless assignments.exists?(['settings ->> ? = ?', "#{kind}_id", id])
    else raise Pundit::NotAuthorizedError
    end
  end
end

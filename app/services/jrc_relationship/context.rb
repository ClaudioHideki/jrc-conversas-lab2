class JrcRelationship::Context
  attr_reader :member, :account, :user

  def initialize(member)
    @member = AccountUser.find_by!(id: member.id, account_id: member.account_id, user_id: member.user_id)
    @account, @user = @member.account, @member.user
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
    if [JrcRelationship::Renewal, JrcRelationship::ExpansionSignal].include?(model) && !JrcOperations::Access.crm?(member)
      return relation.none
    end
    visibility = JrcCustomers::Visibility.new(account: account, user: user, account_user: member)
    if model == JrcRelationship::Renewal
      relation = relation.where(contract_id: visibility.crm(account.jrc_crm_contracts).select(:id))
    elsif model == JrcRelationship::ExpansionSignal
      relation = relation.where(deal_id: nil).or(relation.where(deal_id: visibility.crm(account.jrc_crm_deals).select(:id)))
    elsif model == JrcRelationship::SuccessPlan
      relation = relation.where(project_id: nil).or(relation.where(project_id: visibility.projects.select(:id)))
      sources = { 'task_id' => visibility.project_tasks(visibility.projects), 'ticket_id' => visibility.tickets,
        'qbr_id' => JrcRelationship::Qbr.where(account: account, assignment_id: assignments.select(:id)),
        'product_id' => visibility.crm? ? account.jrc_crm_products : account.jrc_crm_products.none }
      sources.each do |key, native|
        sql = native.reselect(native.klass.arel_table[:id]).reorder(nil).to_sql
        relation = relation.where("NOT EXISTS (SELECT 1 FROM jsonb_array_elements(jrc_relationship_success_plans.goals) AS goal(value) " \
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
    assignment_id = record.is_a?(JrcRelationship::Assignment) ? record.id : record.try(:assignment_id) || record.try(:metadata)&.dig('relationship_assignment_id')
    JrcCustomers::Audit.record!(account: account, actor: user, resource: record, event_type: 'relationship_updated',
                               from_value: before, to_value: after,
                               metadata: { action: action, assignment_id: assignment_id })
  end

  def access_signature
    require 'digest'
    @access_signature ||= Digest::SHA256.hexdigest([member.role, member.custom_role_id, member.custom_role&.updated_at,
      member.permissions.sort, account[:feature_flags], account[:feature_flags_ext_1],
      account.custom_attributes[JrcCrm::OrganizationalStructureService::SETTINGS_KEY],
      account.jrc_crm_user_business_units.where(user_id: user.id).maximum(:updated_at),
      TeamMember.where(team_id: account.teams.select(:id), user_id: user.id).order(:id).pluck(:id, :updated_at),
      JrcServiceDesk::UnitMembership.where(account_id: account.id, account_user_id: member.id).order(:id).pluck(:id, :updated_at),
      JrcProjects::ProjectMember.where(account_id: account.id, user_id: user.id).order(:id).pluck(:id, :updated_at),
      InboxMember.where(inbox_id: account.inboxes.select(:id), user_id: user.id).order(:id).pluck(:id, :updated_at)].join(':'))
  end

  def configuration(assignment = nil)
    product = assignment&.settings&.dig('product_id')
    configurations = @configurations ||= JrcRelationship::Configuration.where(account_id: account.id).index_by(&:scope_key)
    product_config = configurations["product:#{product}"] if product
    return product_config if product_config
    segment = assignment&.settings&.dig('segment_id')
    key = segment ? "segment:#{segment}" : 'account'
    configurations[key] || configurations['account'] ||
      JrcRelationship::Configuration.new(account: account, scope_key: 'account')
  end
end

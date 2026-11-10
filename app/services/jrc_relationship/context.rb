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
    JrcRelationship::LocalAccess.authorize_assignment!(self, record, 'work') if write

    record
  end

  def records(model, survey_action: 'response')
    relation = model.where(account_id: account.id, assignment_id: assignments.select(:id))
    relation = JrcRelationship::RecordVisibility.new(self).source_scope(model, relation, survey_action: survey_action)
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
    event = JrcCustomers::Audit.record!(account: account, actor: user, resource: record, event_type: 'relationship_updated',
                                        from_value: before, to_value: after,
                                        metadata: { action: action, assignment_id: assignment_id })
    JrcRelationship::PortfolioHistoryDetails.capture!(event, resource: record)
    event
  end

  def access_signature
    require 'digest'
    @access_signature ||= eligibility_digest(
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
       JrcRelationship::SurveyDefinition.where(account_id: account.id).where("jsonb_exists(settings, 'service_desk_model')").order(:id).pluck(:id, :version),
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
    segment_config = configurations["segment:#{segment}"] if segment
    choices = [segment_config, customer_configuration(assignment, configurations), configurations['account']]
    choices.compact.first ||
      JrcRelationship::Configuration.new(account: account, scope_key: 'account')
  end

  # Overlay only an authorized unsaved configuration. Native precedence and
  # every permission/source scope remain those of a fresh real Context.
  def for_health_configuration_preview(draft)
    authorize_configuration_scope!(draft.scope_key)
    raise ArgumentError, 'Preview requires an unsaved valid configuration from this account' unless
      (draft.new_record? || draft.changed?) && draft.account_id == account.id && draft.valid?

    preview = self.class.new(member)
    configurations = JrcRelationship::Configuration.where(account_id: account.id).index_by(&:scope_key)
    preview.instance_variable_set(:@configurations, configurations.merge(draft.scope_key => draft))
    preview
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
    JrcRelationship::ConfigurationScope.authorize_corporate!(self, kind, id)
    return JrcRelationship::PortfolioGroupConfiguration.authorize!(self, scope_key) if kind == 'portfolio'
    return if policy.admin?

    case kind
    when 'company' then assignments.find_by!(company_id: id)
    when 'unit' then assignments.find_by!(business_unit_id: id)
    when 'team' then account.teams.joins(:team_members).where(team_members: { user_id: user.id }).find(id)
    when 'segment', 'product'
      raise Pundit::NotAuthorizedError unless assignments.exists?(['settings ->> ? = ?', "#{kind}_id", id])
    else raise Pundit::NotAuthorizedError
    end
  end

  private

  def eligibility_digest(value)
    local_rules = JrcRelationship::LocalAccess.signature(member)
    value = "#{value}:local_role_policies:#{local_rules.to_json}" if local_rules.any?
    version = member.jrc_relationship_eligibility_version
    value = "#{value}:relationship_eligibility:#{version}" if version.positive?
    Digest::SHA256.hexdigest(value)
  end
end

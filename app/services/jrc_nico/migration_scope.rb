# Composes imported-record acceptance with tenant and typed-parent ownership.
class JrcNico::MigrationScope
  def initialize(relation, account:)
    @relation = relation.all
    @account = account
    @model = @relation.klass
  end

  def call
    return attachments if @model == ActiveStorage::Attachment

    relation = accepted(tenant_scope)
    return relation if @model == Contact || @model.table_name == 'companies'
    return audit_events(relation) if @model == JrcProjects::AuditEvent

    relation = apply_references(relation)
    @model == JrcRelationship::Assignment ? assignments(relation) : relation
  end

  private

  def apply_references(relation)
    references.reduce(relation) do |scope, (key, target)|
      next scope unless @model.column_names.include?(key.to_s)

      scope.where(key => nil).or(scope.where(key => target.reselect(target.klass.arel_table[:id]).reorder(nil)))
    end
  end

  def visible(model)
    JrcNico::MigrationVisibility.scope(model, account: @account)
  end

  def tenant_scope
    return @relation.where(campaign_id: @account.jrc_campaigns.select(:id)) if @model == JrcCampaigns::Recipient

    @relation.where(account_id: @account.id)
  end

  def accepted(relation)
    domain = if @model == Contact
               'contacts'
             elsif @model.table_name == 'companies'
               'companies'
             else
               JrcNico::MigrationVisibility::DOMAINS[@model.name]
             end
    domain ? JrcMigrations::Visibility.scope(relation, account: @account, domain: domain) : relation
  end

  def attachments
    # No account_id on Attachment: typed parents and the adapter both scope it.
    projects = @relation.where(record_type: 'JrcProjects::Project', record_id: visible(JrcProjects::Project).select(:id))
    tasks = @relation.where(record_type: 'JrcProjects::Task', record_id: visible(JrcProjects::Task).select(:id))
    JrcMigrations::Visibility.scope(projects, account: @account, domain: 'project_attachments')
                             .or(JrcMigrations::Visibility.scope(tasks, account: @account, domain: 'project_task_attachments'))
  end

  def audit_events(relation)
    relation.where(auditable_type: 'JrcProjects::Project', auditable_id: visible(JrcProjects::Project).select(:id))
            .or(relation.where(auditable_type: 'JrcProjects::Task', auditable_id: visible(JrcProjects::Task).select(:id)))
  end

  def references
    refs = { contact_id: visible(Contact), requester_id: visible(Contact), company_id: visible(JrcCustomers::Company) }
    JrcNico::MigrationVisibility::PARENTS.fetch(@model.name, {}).each { |key, type| refs[key] = visible(type.constantize) }
    if @model.name.start_with?('JrcRelationship::') && @model.column_names.include?('assignment_id')
      refs[:assignment_id] = visible(JrcRelationship::Assignment)
    end
    refs
  end

  def assignments(relation)
    # Company aggregates include linked contacts and cached summaries.
    pending = @account.contacts.where.not(id: visible(Contact).select(:id)).where.not(company_id: nil).select(:company_id)
    relation.where(company_id: nil).or(relation.where.not(company_id: pending))
  end
end

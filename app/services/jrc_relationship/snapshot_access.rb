# Historical scores remain readable after normal data updates. Every referenced
# native source is reauthorized before a cached score or NICO result is returned.
class JrcRelationship::SnapshotAccess
  def self.scope(context, relation, column: 'signals', require_manifest: true)
    raise ArgumentError, 'Invalid evidence column' unless %w[signals metadata].include?(column)
    evidence = "#{relation.klass.table_name}.#{column}"
    original = relation
    relation = relation.where("#{evidence} ? '_source_ids'")
    sources(context).each do |key, native_scope|
      sql = native_scope.reselect(native_scope.klass.arel_table[:id]).reorder(nil).to_sql
      relation = relation.where("NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(COALESCE(#{evidence} #> '{_source_ids,#{key}}', '[]'::jsonb)) AS source_id(value) WHERE source_id.value::bigint NOT IN (#{sql}))")
    end
    require_manifest ? relation : relation.or(original.where("NOT (#{evidence} ? '_source_ids')"))
  end

  def self.sources(context)
    visibility = JrcCustomers::Visibility.new(account: context.account, user: context.user, account_user: context.member)
    contracts = visibility.crm(context.account.jrc_crm_contracts)
    orders = visibility.crm(context.account.jrc_crm_sales_orders)
    invoices = JrcCrm::Invoice.where(account_id: context.account.id, contract_id: contracts.select(:id)).or(
      JrcCrm::Invoice.where(account_id: context.account.id, sales_order_id: orders.select(:id)))
    invoices = JrcCrm::OrganizationalVisibility.new(account: context.account, user: context.user, relation: invoices).call unless context.policy.admin?
    projects = visibility.projects
    sources = {
      'conversations' => visibility.conversations, 'activities' => visibility.crm(context.account.jrc_crm_activities, owner: :user_id),
      'contracts' => contracts, 'orders' => orders, 'invoices' => invoices, 'tickets' => visibility.tickets,
      'projects' => projects, 'project_tasks' => visibility.project_tasks(projects),
      'csat' => CsatSurveyResponse.where(account_id: context.account.id, conversation_id: visibility.conversations.select(:id)),
      'messages' => Message.where(account_id: context.account.id, conversation_id: visibility.conversations.select(:id), private: false),
      'ticket_events' => visibility.ticket_events(visibility.tickets),
      'project_events' => JrcProjects::AuditEvent.where(account_id: context.account.id, auditable_type: 'JrcProjects::Project', auditable_id: projects.select(:id)).or(
        JrcProjects::AuditEvent.where(account_id: context.account.id, auditable_type: 'JrcProjects::Task', auditable_id: visibility.project_tasks(projects).select(:id))),
      'surveys' => context.records(JrcRelationship::Survey),
      'plans' => context.records(JrcRelationship::SuccessPlan)
    }
    sources['calls'] = visibility.calls(contact_ids: context.account.contacts.select(:id), conversation_ids: visibility.conversations.select(:id)) if defined?(::Call)
    sources
  end
end

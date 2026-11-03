# Recheck the native evidence manifest before NICO reads historical aggregates.
# This does not change SnapshotAccess or the human Customer360 projection.
module JrcNico::MigrationEvidence
  SOURCES = {
    'conversations' => 'Conversation', 'activities' => 'JrcCrm::Activity', 'contracts' => 'JrcCrm::Contract',
    'orders' => 'JrcCrm::SalesOrder', 'invoices' => 'JrcCrm::Invoice', 'tickets' => 'JrcServiceDesk::Ticket',
    'projects' => 'JrcProjects::Project', 'project_tasks' => 'JrcProjects::Task', 'csat' => 'CsatSurveyResponse',
    'messages' => 'Message', 'ticket_events' => 'JrcServiceDesk::TicketEvent', 'project_events' => 'JrcProjects::AuditEvent',
    'surveys' => 'JrcRelationship::Survey', 'plans' => 'JrcRelationship::SuccessPlan', 'calls' => 'Call'
  }.freeze

  def self.pending?(account)
    ActiveRecord::Base.uncached { JrcMigrations::Mapping.exists?(account: account, accepted_at: nil) }
  end

  def self.authorize!(record, account:)
    column = evidence_column(record)
    if column && pending?(account)
      manifest = record[column].is_a?(Hash) && record[column]['_source_ids']
      raise ActiveRecord::RecordNotFound unless manifest.is_a?(Hash)

      manifest!(manifest, account: account)
    end
    record
  end

  def self.evidence_column(record)
    return 'signals' if record.is_a?(JrcRelationship::HealthSnapshot)
    return 'metadata' if record.is_a?(JrcRelationship::RiskCase) || record.is_a?(JrcRelationship::Action)
  end
  private_class_method :evidence_column

  def self.manifest!(manifest, account:)
    manifest.each do |key, values|
      type = SOURCES[key.to_s]
      raise ActiveRecord::RecordNotFound unless type

      ids = Array(values).uniq
      next if ids.empty?

      allowed = JrcNico::MigrationVisibility.scope(type.constantize, account: account)
      raise ActiveRecord::RecordNotFound unless allowed.where(id: ids).distinct.count == ids.size
    end
  end

  def self.customer!(context, assignment)
    return unless pending?(context.account)

    customer = assignment.customer_context(context.member)
    customer.sources.each_value do |relation|
      allowed = JrcNico::MigrationVisibility.scope(relation, account: context.account)
      raise ActiveRecord::RecordNotFound if relation.where.not(id: allowed.reselect(allowed.klass.arel_table[:id]).reorder(nil)).exists?
    end
    [JrcRelationship::RiskCase, JrcRelationship::Action, JrcRelationship::SuccessPlan, JrcRelationship::Qbr].each do |type|
      context.records(type).where(assignment: assignment).find_each do |record|
        JrcNico::MigrationVisibility.authorize!(record, account: context.account)
      end
    end
  end
end

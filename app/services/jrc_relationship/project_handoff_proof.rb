# Confirms already-settled native project responsibility. This never transfers
# a project, grants membership or rewrites a historical project owner.
class JrcRelationship::ProjectHandoffProof
  BLOCKERS = { 'already_destination' => nil, 'historical' => nil,
               'native_transfer_required' => 'project_responsibility_requires_native_transfer',
               'customer_mismatch' => 'project_customer_context_mismatch',
               'unreviewed_tasks' => 'project_tasks_require_native_transfer' }.freeze

  def initialize(context)
    @context = context
    @visibility = JrcCustomers::Visibility.new(account: context.account, user: context.user, account_user: context.member)
  end

  def capture(assignment, entries, owner_id:, lock: false)
    source_projects(entries, lock).map do |project|
      { 'id' => project.id, 'label' => project.name, 'owner_id' => project.owner_id, 'lock_version' => project.lock_version,
        'state' => state(project, assignment, entries, owner_id), 'digest' => JrcRelationship::PlaybookFlowReference.digest(project.attributes) }
    end
  end

  def self.blockers(proofs)
    proofs.filter_map { |row| BLOCKERS.fetch(row.fetch('state')) }.uniq
  end

  def visible?(proofs)
    return true if proofs.empty?

    ids = proofs.pluck('id')
    @visibility.projects.where(id: ids).count == ids.size
  end

  private

  def source_projects(entries, lock)
    ids = @context.records(JrcRelationship::SuccessPlan).where(id: entries.select { |row| row['kind'] == 'plans' }.pluck('id'))
                  .where.not(project_id: nil).distinct.pluck(:project_id)
    return [] if ids.empty?

    source = JrcProjects::Project.where(account: @context.account, id: ids)
    JrcRelationship::PortfolioResponsibilities.new(@context).authorized!(source, @visibility.projects)
    raise Pundit::NotAuthorizedError unless source.count == ids.size

    source = source.order(:id)
    lock ? source.lock('FOR UPDATE NOWAIT') : source
  end

  def state(project, assignment, entries, owner_id)
    return 'customer_mismatch' unless assignment.customer_context(@context.member).projects.exists?(id: project.id)
    return 'historical' if %w[completed canceled].include?(project.status)
    return 'native_transfer_required' unless project.owner_id == owner_id
    return 'unreviewed_tasks' if unreviewed_tasks?(project, assignment, entries)

    'already_destination'
  end

  def unreviewed_tasks?(project, assignment, entries)
    return false unless assignment.owner_id

    reviewed = entries.select { |row| row['kind'] == 'project_tasks' }.pluck('id')
    tasks = JrcProjects::Task.where(account: @context.account, project: project, assignee_id: assignment.owner_id)
                             .where.not(status: %w[completed canceled]).where.not(id: reviewed)
    JrcRelationship::PortfolioResponsibilities.new(@context).authorized!(tasks, @visibility.project_tasks(@visibility.projects))
    tasks.exists?
  end
end

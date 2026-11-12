# Cursor uses only the last returned visible ID. Never count or expose IDs of
# source-denied executions. The caller retains the native per-result guard.
class JrcRelationship::PlaybookExecutionHistory
  SCAN_LIMIT = 1000
  CHUNK_SIZE = 100

  def initialize(context)
    @context = context
  end

  def call(per_page: 25, before_id: nil, playbook_id: nil, &)
    raise Pundit::NotAuthorizedError unless @context.policy.configure?

    size = Integer(per_page.to_s, 10).clamp(1, 50)
    scope = executions(playbook_id)
    cursor = JrcRelationship::PortfolioOwnerInput.parse(before_id)
    found = scan(scope, cursor, size, &)
    result(found, size)
  end

  private

  def scan(scope, cursor, size)
    found = []
    scanned = 0
    loop do
      batch = (cursor ? scope.where('id < ?', cursor) : scope).limit(CHUNK_SIZE).to_a
      break if batch.empty?
      raise ArgumentError, 'Narrow the playbook filter before reading this execution history' if scanned + batch.size > SCAN_LIMIT

      batch.each do |row|
        found << row if yield(row)
        return found if found.size > size
      end
      scanned += batch.size
      cursor = batch.last.id
    end
    found
  end

  def executions(playbook_id)
    rows = JrcRelationship::PlaybookExecution.where(account: @context.account, assignment_id: @context.assignments.select(:id))
    id = JrcRelationship::PortfolioOwnerInput.parse(playbook_id)
    if id
      JrcRelationship::Playbook.where(account: @context.account).find(id)
      rows = rows.where(playbook_id: id)
    end
    rows.includes(:assignment).order(id: :desc)
  end

  def result(found, size)
    selected = found.first(size)
    { payload: selected, meta: { per_page: size, next_before_id: found.size > size ? selected.last.id : nil } }
  end
end

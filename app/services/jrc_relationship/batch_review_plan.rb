class JrcRelationship::BatchReviewPlan
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
  def initialize(context)
    @context = context
  end

  def normalize(raw)
    input = raw.to_h.deep_stringify_keys
    ids = input.fetch('ids')
    raise ArgumentError, 'Choose 1 to 50 unique customers' unless ids.is_a?(Array) && ids.size.between?(1, 50) && ids.uniq.size == ids.size
    raise ArgumentError, 'Invalid request identity' unless UUID.match?(input.fetch('request_id').to_s)

    operation = input.fetch('operation')
    options = operation_options(operation, input)
    { 'ids' => ids.map { |id| Integer(id) }.sort, 'operation' => operation, 'request_id' => input.fetch('request_id'), **options }
  end

  def snapshot(inputs, lock: false)
    rows = @context.assignments.where(id: inputs.fetch('ids')).order(:id)
    rows = rows.lock if lock
    records = rows.to_a
    raise ActiveRecord::RecordNotFound unless records.size == inputs.fetch('ids').size

    book = book_snapshot(inputs, lock: lock)
    result = { 'version' => 1, 'access_signature' => @context.access_signature, 'book' => book, 'summary' => operation_summary(inputs, book),
               'rows' => records.map { |record| row_snapshot(record) } }
    add_cadence_snapshot(result, inputs, book, lock) if inputs['operation'] == 'cadence'
    result
  end

  def row_snapshot(record)
    customer = record.contact || record.company
    source = record.attributes.slice('id', 'account_id', 'owner_id', 'team_id', 'business_unit_id', 'company_id', 'contact_id',
                                     'status', 'settings', 'updated_at')
    { 'assignment_id' => record.id, 'label' => record.label,
      'digest' => digest([source, customer&.attributes&.slice('id', 'account_id', 'name', 'company_id', 'updated_at')]) }
  end

  def validate!(review, assignment: nil)
    raise ArgumentError, 'Reviewed access changed' unless review.snapshot.fetch('access_signature') == @context.access_signature
    raise ArgumentError, 'Reviewed playbook changed' unless review.snapshot['book'] == book_snapshot(review.inputs, lock: true)

    validate_cadence!(review)

    records = assignment ? [assignment] : reviewed_assignments(review)
    records.each { |record| validate_row!(review, record) }
  end

  def digest(value)
    JrcRelationship::PlaybookFlowReference.digest(value)
  end

  private

  def add_cadence_snapshot(result, inputs, book, lock)
    result['cadence'] = JrcRelationship::CadencePlan.new(@context).snapshot(inputs, lock: lock)
    result['summary'].merge!(result['cadence'].slice('contact_name', 'conversation_number'))
    result['summary']['schedule'] = book.fetch('steps').map do |step|
      { 'title' => step.fetch('title'), 'due_at' => (Time.iso8601(inputs.fetch('starts_at')) + step.fetch('after_days').days).iso8601(6) }
    end
  end

  def validate_cadence!(review)
    return unless review.inputs['operation'] == 'cadence'

    current = JrcRelationship::CadencePlan.new(@context).snapshot(review.inputs, lock: true)
    raise ArgumentError, 'Reviewed conversation changed' unless review.snapshot.fetch('cadence') == current
  end

  def operation_summary(inputs, book)
    case inputs.fetch('operation')
    when 'assign'
      id = inputs['owner_id']
      { 'owner_id' => id, 'owner_name' => id ? @context.assignable_users.find(id).name : nil }
    when 'playbook', 'cadence' then { 'book_name' => book.fetch('name'), 'book_version' => book.fetch('version') }
    else { 'title' => inputs.fetch('title'), 'due_at' => inputs.fetch('due_at') }
    end
  end

  def reviewed_assignments(review)
    ids = review.inputs.fetch('ids')
    records = @context.assignments.where(id: ids).order(:id).lock.to_a
    raise ActiveRecord::RecordNotFound unless records.size == ids.size

    records
  end

  def validate_row!(review, record)
    original = review.snapshot.fetch('rows').find { |row| row.fetch('assignment_id') == record.id }
    raise ArgumentError, 'Reviewed customer changed' unless original && original == row_snapshot(record)
  end

  def operation_options(operation, input)
    case operation
    when 'assign'
      assign_options(input)
    when 'activity'
      title = input.fetch('title').to_s.strip
      raise ArgumentError, 'Activity title is required' unless title.length.between?(1, 250)

      { 'title' => title, 'due_at' => Time.iso8601(input.fetch('due_at')).iso8601(6) }
    when 'playbook' then { 'playbook_id' => selected_book(input) }
    when 'cadence'
      { 'playbook_id' => selected_book(input), 'conversation_id' => Integer(input.fetch('conversation_id')),
        'starts_at' => Time.iso8601(input.fetch('starts_at')).iso8601(6) }
    else raise ArgumentError, 'Unsupported portfolio operation'
    end
  end

  def assign_options(input)
    raise Pundit::NotAuthorizedError unless @context.policy.team?

    { 'owner_id' => input['owner_id'].present? ? @context.assignable_users.find(input['owner_id']).id : nil }
  end

  def book_snapshot(inputs, lock: false)
    return unless %w[playbook cadence].include?(inputs.fetch('operation'))

    scope = JrcRelationship::Playbook.where(account_id: @context.account.id, active: true)
    book = (lock ? scope.lock('FOR SHARE') : scope).find(inputs.fetch('playbook_id'))
    if book.steps.any? { |step| step['kind'] == 'flow' }
      raise ArgumentError, 'Customer-facing Flow requires its separate per-conversation preview and approval'
    end

    JSON.parse(book.snapshot.to_json)
  end

  def selected_book(input)
    JrcRelationship::Playbook.where(account_id: @context.account.id).find(input.fetch('playbook_id')).id
  end
end

class JrcRelationship::BatchNativeReceipt
  MODELS = { 'JrcRelationship::Action' => JrcRelationship::Action, 'JrcRelationship::RiskCase' => JrcRelationship::RiskCase,
             'JrcRelationship::SuccessPlan' => JrcRelationship::SuccessPlan }.freeze

  def initialize(context, review, item)
    @context = context
    @review = review
    @item = item
  end

  def call
    operation = @review.inputs.fetch('operation')
    resources = case operation
                when 'assign' then [assignment_receipt]
                when 'activity' then [activity_receipt]
                when 'playbook' then playbook_receipts
                else raise ArgumentError, 'Unsupported native receipt'
                end
    { 'updated' => 1, 'operation' => operation, 'assignment_id' => @item.assignment_id, 'resources' => resources }
  end

  private

  def assignment_receipt
    record = @context.assignment(@item.assignment_id, write: true).reload
    raise ArgumentError, 'Native assignment did not match review' unless record.owner_id == @review.inputs['owner_id']

    { 'resource_type' => record.class.name, 'resource_id' => record.id, 'owner_id' => record.owner_id }
  end

  def activity_receipt
    key = "activity:portfolio:reviewed:#{@review.id}:#{@item.id}:#{@item.assignment_id}"
    action = JrcRelationship::Action.find_by(account_id: @context.account.id, assignment_id: @item.assignment_id, source_key: key)
    activity = action&.activity
    raise ArgumentError, 'Native activity was not created' unless activity && activity.account_id == @context.account.id

    { 'resource_type' => activity.class.name, 'resource_id' => activity.id }
  end

  def playbook_receipts
    book = @review.snapshot.fetch('book')
    source_key = "manual:reviewed:#{@review.id}:#{@item.id}"
    execution = JrcRelationship::PlaybookExecution.find_by(account_id: @context.account.id, assignment_id: @item.assignment_id,
                                                           playbook_id: book.fetch('id'), version: book.fetch('version'), source_key: source_key)
    raise ArgumentError, 'Native playbook did not produce an execution' unless execution

    results = execution.snapshot.fetch('results')
    raise ArgumentError, 'Native playbook step count mismatch' unless results.size == book.fetch('steps').size

    results.map { |result| verified_step(result) }
  end

  def verified_step(result)
    model = MODELS[result['resource_type']]
    record = model&.find_by(account_id: @context.account.id, assignment_id: @item.assignment_id, id: result['resource_id'])
    raise ArgumentError, 'Native playbook step was blocked' unless result['state'] == 'planned' && record

    result.slice('step_key', 'resource_type', 'resource_id', 'activity_id')
  end
end

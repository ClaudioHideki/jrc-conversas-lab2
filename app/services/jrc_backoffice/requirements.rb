class JrcBackoffice::Requirements
  class Conflict < StandardError; end
  class Blocked < StandardError; end

  def self.current(request)
    JrcBackoffice::RequirementPlan.where(account_id: request.account_id, backoffice_request_id: request.id).order(version: :desc).first
  end

  # Called in the create transaction. Existing requests are not migrated or
  # silently given a different checklist; adoption requires an explicit action.
  def self.capture_initial!(request)
    return unless request.workflow_version == 2

    JrcBackoffice::RequirementCatalog.lock!(request.account_id)
    new(request: request, actor: request.requested_by).send(:persist_plan!, reason: 'Initial configured requirement snapshot')
  end

  def self.documents(request)
    plan = current(request)
    return [] unless plan

    plan.entries.filter_map do |entry|
      definition = entry.fetch('definition')
      next unless JrcBackoffice::RequirementDefinition.leaf_kind(definition) == 'document'

      # Conditions are evaluated by the requirement gate, not by document upload.
      { 'key' => definition.fetch('document_key'), 'label' => definition.fetch('label'), 'source' => 'manual',
        'required' => false, 'blocking' => false, 'requirement_rule_key' => entry.fetch('key') }
    end.uniq { |row| row['key'] }
  end

  def self.manifest(request:, actor:)
    return nil unless current(request)

    result = new(request: request, actor: actor).projection(through: 'finance', verify_bytes: true)
    { plan_revision: result[:plan_revision], digest: result[:digest], stale: result[:stale],
      items: result[:items].map { |item| item.slice(:key, :status, :blocking, :response_revision) } }
  end

  def self.required_stage?(request, stage)
    return false unless JrcBackoffice::RequirementDefinition::STAGES.include?(stage)

    plan = current(request)
    plan && plan.entries.any? do |entry|
      row = entry.fetch('definition')
      row['required'] && row['blocking'] && row['stage'] == stage
    end
  end

  def self.blocking_messages(request:, actor:)
    return [] unless request.workflow_version == 2 && current(request)
    return [] if %w[request analysis].include?(request.stage)

    through = JrcBackoffice::RequirementDefinition::STAGES.include?(request.stage) ? request.stage : 'finance'
    result = new(request: request, actor: actor).projection(through: through)
    return ['A origem mudou. Revise o checklist configurado antes de avançar.'] if result[:stale]

    result[:items].select { |item| item[:blocking] }.map { |item| "Requisito pendente: #{item[:definition]['label']}" }
  end

  def self.check!(request:, actor:, through:)
    return unless request.workflow_version == 2 && current(request)

    result = new(request: request, actor: actor).projection(through: through, verify_bytes: true)
    raise Blocked, 'Requirement sources changed; review the checklist again' if result[:stale]
    raise Blocked, 'Required Backoffice items are pending or unavailable' if result[:items].any? { |item| item[:blocking] }
  end

  # A signature cannot be required to send itself. All other due requirements,
  # except the post-signature release gate, are checked before send admission.
  def self.check_before_signature!(request:, actor:)
    return unless request.workflow_version == 2 && current(request)

    result = new(request: request, actor: actor).projection(through: 'contract', verify_bytes: true)
    raise Blocked, 'Requirement sources changed; review the checklist again' if result[:stale]
    pending = result[:items].any? do |item|
      item[:blocking] && !JrcBackoffice::RequirementDefinition.post_signature?(item[:definition])
    end
    raise Blocked, 'Required Backoffice items are pending or unavailable' if pending
  end

  def initialize(request:, actor:)
    @request, @actor = request, actor
    @access = JrcBackoffice::ContractAccess.new(account: request.account, actor: actor)
  end

  def projection(through: nil, verify_bytes: false)
    @request = @access.request(@request.id)
    plan = self.class.current(@request)
    return { configured: false, plan_revision: 0, items: [], stale: false, can_adopt: can_adopt? } unless plan

    native = JrcBackoffice::NativeRequirements.new(request: @request, actor: @actor, verify_bytes: verify_bytes)
    responses = latest_responses(plan)
    rows = JrcBackoffice::RequirementEvaluation.new(rows: plan.entries, facts: native.facts, responses: responses, source: native)
                                            .call(through: through)
    stale = plan.entries.any? && plan.source_facts != native.facts
    unless stale
      rows.each do |row|
        answer = responses[row[:key]]
        next unless answer

        row[:answer] = answer.slice('value', 'decision', 'note')
      end
    end
    rows.each { |row| row[:can_answer] = can_answer_definition?(row[:definition]) }
    @access.request(@request.id)
    { configured: true, plan_revision: plan.version, digest: plan.digest, items: rows, stale: stale,
      can_adopt: can_adopt?, can_answer: @access.writable?(@request), created_at: plan.created_at.iso8601(6) }
  end

  def adopt!(expected_revision:, reason:)
    reason!(reason)
    revision!(expected_revision)
    mutate do
      raise ArgumentError, 'Reopen the documentation stage before adopting new requirements' unless can_adopt?
      plan = self.class.current(@request)
      raise Conflict, 'The checklist changed; reload before adopting' unless (plan&.version || 0) == expected_revision

      persist_plan!(reason: reason.strip)
    end
    projection
  end

  def answer!(key:, expected_plan_revision:, expected_response_revision:, payload:, reason:)
    reason!(reason)
    revision!(expected_plan_revision)
    revision!(expected_response_revision)
    mutate do
      plan = self.class.current(@request)
      raise Conflict, 'The checklist changed; reload before answering' unless plan && plan.version == expected_plan_revision
      if plan.source_facts != JrcBackoffice::NativeRequirements.new(request: @request, actor: @actor).facts
        raise Conflict, 'Requirement sources changed; review the checklist again'
      end
      raise ActiveRecord::RecordNotFound unless plan.entries.any? { |row| row['key'] == key }

      entry = plan.entries.find { |item| item['key'] == key }
      definition = entry.fetch('definition')
      if JrcBackoffice::RequirementDefinition::HUMAN_KINDS.include?(JrcBackoffice::RequirementDefinition.leaf_kind(definition))
        @request.account.account_users.where(user_id: @actor.id).lock('FOR SHARE').load
        TeamMember.where(user_id: @actor.id, team_id: @request.account.teams.where(id: definition['reviewer_team_ids']).select(:id)).lock('FOR SHARE').load
        @actor.lock!('FOR SHARE')
      end
      raise Pundit::NotAuthorizedError unless can_answer_definition?(definition)
      previous = plan.responses.where(requirement_key: key).order(revision: :desc).first
      raise Conflict, 'This answer changed; reload before saving' unless (previous&.revision || 0) == expected_response_revision

      response = plan.responses.create!(account_id: @request.account_id, actor: @actor, requirement_key: key,
        revision: expected_response_revision + 1, payload: payload.to_h.stringify_keys, reason: reason.strip)
      raise Pundit::NotAuthorizedError unless can_answer_definition?(definition)
      audit!('requirement_answered', plan: plan, response: response)
    end
    projection
  end

  def response_history(key:, plan_revision:, page: 1)
    revision!(plan_revision)
    @request = @access.request(@request.id)
    plan = @request.requirement_plans.find_by!(account_id: @request.account_id, version: plan_revision)
    native = JrcBackoffice::NativeRequirements.new(request: @request, actor: @actor)
    raise Pundit::NotAuthorizedError unless plan.source_facts == native.facts

    entry = plan.entries.find { |row| row['key'] == key }
    raise ActiveRecord::RecordNotFound unless entry

    rows = plan.responses.where(requirement_key: key).order(revision: :desc)
    total = rows.count
    pages = [(total / 20.0).ceil, 1].max
    number = Integer(page.to_s, 10).clamp(1, pages)
    data = rows.offset((number - 1) * 20).limit(20).includes(:actor).map do |row|
      { revision: row.revision, payload: row.payload, reason: row.reason, at: row.created_at.iso8601(6) }
    end
    @request = @access.request(@request.id)
    raise Pundit::NotAuthorizedError unless plan.source_facts == JrcBackoffice::NativeRequirements.new(request: @request, actor: @actor).facts

    { request_id: @request.id, key: key, plan_revision: plan.version, definition: entry.fetch('definition'),
      data: data, meta: { page: number, pages: pages, total: total, per_page: 20 } }
  end

  private

  def can_answer_definition?(definition)
    return false unless @access.writable?(@request)
    return true unless JrcBackoffice::RequirementDefinition::HUMAN_KINDS.include?(JrcBackoffice::RequirementDefinition.leaf_kind(definition))
    @actor.reload
    return false unless @actor.active_for_authentication?
    return false unless AccountUser.exists?(account_id: @request.account_id, user_id: @actor.id)
    return true if Array(definition['reviewer_ids']).include?(@actor.id)
    TeamMember.where(user_id: @actor.id, team_id: @request.account.teams.where(id: definition['reviewer_team_ids']).select(:id)).exists?
  end

  def mutate
    @request.sales_order.with_lock('FOR NO KEY UPDATE') do
      @request.with_lock('FOR NO KEY UPDATE') do
        JrcBackoffice::RequirementCatalog.lock!(@request.account_id)
        @access.writable!(@request)
        yield
        @access.writable!(@request)
      end
    end
  end

  def persist_plan!(reason:)
    current = self.class.current(@request)
    entries = JrcBackoffice::RequirementCatalog.matching(@request).map do |rule|
      { 'key' => rule.rule_key, 'rule_id' => rule.id, 'rule_version' => rule.version,
        'scope' => { 'customer_kind' => rule.customer_kind }, 'definition' => rule.definition }
    end.sort_by { |entry| entry.fetch('key') }
    facts = JrcBackoffice::NativeRequirements.new(request: @request, actor: @actor).facts
    digest = JrcBackoffice::RequirementDefinition.digest({ 'entries' => entries, 'source_facts' => facts })
    return current if current&.digest == digest

    plan = JrcBackoffice::RequirementPlan.create!(account_id: @request.account_id, backoffice_request: @request, created_by: @actor,
      version: (current&.version || 0) + 1, entries: entries, source_facts: facts, digest: digest, reason: reason)
    audit!('requirement_plan_captured', plan: plan)
    plan
  end

  def latest_responses(plan)
    plan.responses.select('DISTINCT ON (requirement_key) jrc_backoffice_requirement_responses.*')
        .order(:requirement_key, revision: :desc).to_h do |row|
      [row.requirement_key, row.payload.merge('revision' => row.revision)]
    end
  end

  def can_adopt?
    @request.workflow_version == 2 && @access.writable?(@request) && %w[request analysis documentation].include?(@request.stage)
  end

  def reason!(value)
    raise ArgumentError, 'Provide an explicit reason of at most 4000 characters' unless JrcBackoffice::RequirementDefinition.text?(value, 4000)
  end

  def revision!(value)
    raise ArgumentError, 'An integer revision is required' unless value.is_a?(Integer) && value >= 0
  end

  def audit!(action, plan:, response: nil)
    JrcCrm::AuditEvent.create!(account_id: @request.account_id, actor_type: 'User', actor_id: @actor.id,
      event_type: 'backoffice_updated', resource_type: @request.class.name, resource_id: @request.id,
      from_value: {}, to_value: { plan_id: plan.id, version: plan.version, digest: plan.digest, response_id: response&.id },
      metadata: { source: 'backoffice_requirements', action: action })
  end
end

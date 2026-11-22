# frozen_string_literal: true

# Read-only domain hooks for the one native Central engine. No policy, approver or grant is installed.
class JrcContactCenter::PauseApprovalCatalog
  FIELDS = { 'context_digest' => 'string', 'current_context_digest' => 'string', 'evidence_state' => 'string',
             'pause_request_id' => 'integer', 'reason_code' => 'string', 'reason_label' => 'string',
             'scope_unit_ids' => 'string_list', 'scope_unit_names' => 'string_list',
             'unit_count' => 'integer', 'justification_digest' => 'string' }.freeze

  def self.install!
    key = JrcContactCenter::PauseApprovalPolicyCheck::KEY
    model = JrcContactCenter::PauseApprovalScope
    entries = JrcApprovals::Catalog.instance_variable_get(:@entries)
    return if entries[key]&.model.equal?(model)
    raise JrcApprovals::Error, 'DUPLICATE_CATALOG' if entries[key] && entries[key].model&.name != model.name

    JrcApprovals::Catalog.instance_variable_get(:@mutex).synchronize { entries.delete(key) }
    register!(key, model)
  end

  def self.register!(key, model)
    JrcApprovals::Catalog.register(key: key, version: 1, model: model, fields: FIELDS,
                                   authorize: ->(actor, scope) { JrcContactCenter::PauseApprovalSourceAccess.allowed?(scope, actor) },
                                   request_authorize: ->(actor, scope) { scope.review.actor_user_id == actor.id },
                                   capture: ->(scope, actor) { capture(scope, actor) },
                                   verify: ->(scope, actor) { verify!(scope, actor) })
  end

  private_class_method :register!

  def self.capture(scope, actor)
    raise Pundit::NotAuthorizedError unless JrcContactCenter::PauseApprovalSourceAccess.allowed?(scope, actor)

    review = scope.review
    current = JrcContactCenter::PauseApprovalSourceCurrent.new(review).call
    intent = review.payload.fetch('intent')
    values = { context_digest: review.context_digest, current_context_digest: current.fetch('digest'),
               evidence_state: current.fetch('current') ? 'current' : 'stale', pause_request_id: review.deferred_pause_request_id,
               reason_code: intent.fetch('reason_code'), reason_label: review.payload.fetch('selection').fetch('reason_label'),
               scope_unit_ids: scope.unit_ids, scope_unit_names: unit_names(scope), unit_count: scope.unit_ids.size,
               justification_digest: JrcApprovals::Ledger.digest('justification' => intent.fetch('justification')) }
    { issuer_company_id: scope.issuer_company_id, business_unit_id: scope.business_unit_id, values: values }
  end

  def self.unit_names(scope)
    scope.review.payload.fetch('coverage').fetch('units').select { |unit| scope.unit_ids.include?(unit.fetch('id')) }.pluck('name')
  end
  private_class_method :unit_names

  def self.verify!(scope, actor)
    values = capture(scope, actor).fetch(:values)
    raise JrcApprovals::Error, 'EVIDENCE_UNVERIFIED' unless values.fetch(:evidence_state) == 'current'

    true
  end
end

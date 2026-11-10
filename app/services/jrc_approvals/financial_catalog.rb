# New entries rather than changing snapshots of already opened price requests.
class JrcApprovals::FinancialCatalog
  EVENTS = { 'crm.proposal_terms' => 'JrcCrm::Proposal', 'crm.order_terms' => 'JrcCrm::SalesOrder' }.freeze
  BASE_FIELDS = { 'context_digest' => 'string', 'price_status' => 'string', 'currency' => 'string', 'total_cents' => 'integer',
    'payment_condition' => 'string', 'payment_method' => 'string', 'installments_count' => 'integer' }.freeze
  def self.install!
    EVENTS.each do |key, model_name|
      model = model_name.constantize # Fixed server map only.
      entries = JrcApprovals::Catalog.instance_variable_get(:@entries)
      next if entries[key]&.model.equal?(model)
      JrcApprovals::Catalog.instance_variable_get(:@mutex).synchronize { entries.delete(key) }
      extra = key == 'crm.proposal_terms' ? { 'first_billing_days' => 'integer' } : { 'first_due_date' => 'string' }
      JrcApprovals::Catalog.register(key: key, version: 1, model: model, fields: BASE_FIELDS.merge(extra),
        authorize: ->(actor, resource) { JrcApprovals::CommercialCatalog.authorized?(actor, resource) },
        request_authorize: ->(actor, resource) { editable?(resource, actor) },
        capture: ->(resource) { capture(resource, key) }, verify: ->(resource, actor) { JrcApprovals::CommercialCatalog.authorized?(actor, resource) && mutable?(resource) })
    end
  end
  def self.mutable?(resource)
    resource.is_a?(JrcCrm::Proposal) ? !resource.locked_for_editing? : !JrcCrm::OrderDiscountMutation.locked?(resource)
  end
  def self.editable?(resource, actor)
    if resource.is_a?(JrcCrm::Proposal)
      JrcCrm::ProposalMutation.authorize!(resource, actor)
      !resource.locked_for_editing?
    else
      JrcCrm::OrderDiscountMutation.authorize!(resource, actor)
      !JrcCrm::OrderDiscountMutation.locked?(resource)
    end
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    false
  end
  def self.values(resource)
    row = resource.attributes.slice('payment_condition', 'payment_method', 'installments_count', 'first_billing_days')
    row['first_due_date'] = resource.snapshot.to_h['first_due_date'] if resource.is_a?(JrcCrm::SalesOrder)
    row
  end
  def self.capture(resource, key)
    native = JrcApprovals::CommercialCatalog.capture(resource)
    terms = values(resource)
    names = JrcApprovals::AdjustmentPolicy::SOURCES.fetch(key)
    selected = terms.slice(*names)
    names.each { |field| selected[field] ||= field.end_with?('_days') ? 0 : '' }
    native[:values] = { context_digest: JrcApprovals::Ledger.digest(native[:values].merge('terms' => selected)),
      price_status: native[:values][:price_status], currency: native[:values][:currency], total_cents: native[:values][:total_cents] }.merge(selected)
    native
  end
end

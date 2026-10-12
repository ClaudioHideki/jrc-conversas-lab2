module JrcApprovalsCommercialHelpers
  def commercial_fixture(scope, author, discount: 200, minimum: 900)
    scope[:account].enable_features!('jrc_crm')
    contact = create(:contact, account: scope[:account])
    product = create(:jrc_crm_product, account: scope[:account], sku: SecureRandom.hex(6), unit_price_cents: 1000,
      minimum_price_cents: minimum, maximum_discount_percent: 100, discount_approval_percent: 100,
      billing_model: 'one_time', sales_unit: 'unidade')
    proposal = JrcCrm::Proposal.create!(account: scope[:account], contact: contact, owner: author.user,
      business_unit: scope[:unit], title: 'Synthetic commercial proposal')
    proposal.proposal_items.create!(product: product, name_snapshot: product.name, unit_price_cents: 1000,
      quantity: 1, discount_cents: discount, billing_model: 'one_time', unit_name: 'unidade')
    { proposal: proposal.reload, product: product, contact: contact }
  end

  def commercial_policy(scope, author, approvers, key: 'crm.proposal_send', selection: 'exclusive', code: SecureRandom.hex(5))
    scope[:account].enable_features!('jrc_crm')
    module_key, event_key = key.split('.', 2)
    definition = approval_definition(approvers, selection: selection)
    manager = JrcApprovals::Policies.new(account: scope[:account], user: author.user)
    policy = manager.create!(code: code, name: 'Synthetic commercial gate', module_key: module_key, event_key: event_key,
      issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id, definition: definition)
    manager.validate!(policy_id: policy.id, expected_version: policy.lock_version)
    manager.publish!(policy_id: policy.id, expected_version: policy.reload.lock_version)
  end

  def commercial_mode(account, key, mode)
    account.update!(custom_attributes: account.custom_attributes.deep_merge('jrc_approval_gates' => { key => mode }))
  end

  def commercial_request(scope, author, resource, key: 'crm.proposal_send', idempotency_key: SecureRandom.hex(6))
    JrcApprovals::CommercialGate.new(account: scope[:account], user: author.user)
      .request!(key: key, resource_id: resource.id, idempotency_key: idempotency_key)
  end
end

RSpec.configure { |config| config.include JrcApprovalsCommercialHelpers, commercial_approvals: true }

class JrcApprovals::CommercialInvalidation
  def self.reference_changed!(product:, user:)
    account = product.account
    return unless account.feature_enabled?('jrc_approvals')

    proposal_ids = JrcCrm::ProposalItem.where(product_id: product.id,
      proposal_id: JrcCrm::Proposal.where(account_id: account.id).select(:id)).distinct.pluck(:proposal_id)
    order_ids = JrcCrm::OrderItem.where(product_id: product.id,
      sales_order_id: JrcCrm::SalesOrder.where(account_id: account.id).select(:id)).distinct.pluck(:sales_order_id)
    deal_ids = JrcCrm::DealProduct.where(product_id: product.id,
      deal_id: JrcCrm::Deal.where(account_id: account.id).select(:id)).distinct.pluck(:deal_id)
    JrcApprovals::CommercialCatalog::EVENTS.each do |key, model_name|
      model = JrcApprovals::Catalog.fetch(key).model
      relation = model.where(account_id: account.id)
      relation = case model_name
                 when 'JrcCrm::Proposal' then relation.where(id: proposal_ids)
                 when 'JrcCrm::Deal' then relation.where(id: deal_ids)
                 when 'JrcCrm::SalesOrder' then relation.where(id: order_ids)
                 else relation.where(sales_order_id: order_ids)
                 end
      relation.find_each do |resource|
        next unless JrcApprovals::CommercialCatalog.authorized?(user, resource)

        JrcApprovals::Requests.new(account: account, user: user)
          .invalidate_resource!(key: key, resource_id: resource.id, reason: 'Native product price reference changed')
      end
    end
  end

  def self.call(resource:, user:)
    return unless resource.account.feature_enabled?('jrc_approvals')

    JrcApprovals::CommercialCatalog::EVENTS.each do |key, model_name|
      next unless resource.class.name == model_name

      JrcApprovals::Requests.new(account: resource.account, user: user)
        .invalidate_resource!(key: key, resource_id: resource.id, reason: 'Native commercial context changed')
    end
  end
end

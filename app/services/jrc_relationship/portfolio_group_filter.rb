# A named group only narrows the existing native assignment scope.
class JrcRelationship::PortfolioGroupFilter
  def self.call(context, scope, id)
    return scope if id.nil? || id == ''

    group_id = JrcRelationship::PortfolioOwnerInput.parse(id)
    group = JrcRelationship::PortfolioGroupScope.resolve(context).find(group_id)
    links = group.customer_links.where(account_id: context.account.id, active: true)
    scope.where(id: links.select(:assignment_id))
  end
end

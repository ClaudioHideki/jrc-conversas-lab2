class JrcRelationship::PortfolioGroupAccess
  def self.complete_management!(context, id)
    group = JrcRelationship::PortfolioGroupScope.writable(context).find(id)
    links = group.customer_links.where(active: true)
    raise Pundit::NotAuthorizedError if links.where.not(assignment_id: context.assignments.select(:id)).exists?

    group
  end
end

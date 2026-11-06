# Reloads the current selected native subjects and group revision only. It is not
# a capacity simulation, formal approval, durable execution queue or write grant.
class JrcRelationship::PortfolioGroupCustomerReview
  def initialize(context)
    @account_id = context.account.id
    @actor_id = context.user.id
  end

  def call(id, ids:)
    selected = JrcRelationship::PortfolioGroupCustomerInput.parse(ids)
    JrcRelationship::PortfolioGroup.transaction do
      JrcRelationship::BatchReviewAuthority.new(account_id: @account_id, actor_id: @actor_id, write: false).call do |context|
        group = JrcRelationship::PortfolioGroupScope.writable(context).find(id)
        raise ArgumentError, 'Archived portfolios cannot change their customer links' unless group.status == 'active'

        rows = selected_rows(context, selected)
        links = group.customer_links.where(assignment_id: selected, active: true).pluck(:assignment_id)
        { group: { id: group.id, version: group.lock_version },
          payload: rows.map { |row| { id: row.id, name: row.label, linked: links.include?(row.id) } } }
      end
    end
  end

  private

  def selected_rows(context, ids)
    rows = context.assignments.where(id: ids).includes(:company, :contact).order(:id).to_a
    raise ActiveRecord::RecordNotFound unless rows.size == ids.size

    rows
  end
end

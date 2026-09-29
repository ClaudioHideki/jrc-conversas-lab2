module Api::V1::Accounts::Crm
  class CustomersController < BaseController
    def show
      contact = crm_scope.contacts.find(params[:id])
      authorize contact, :show?

      deals = visible_to_current_user(crm_scope.jrc_crm_deals)
                       .left_outer_joins(:deal_contacts)
                       .where('jrc_crm_deals.contact_id = :contact_id OR jrc_crm_deal_contacts.contact_id = :contact_id', contact_id: contact.id)
                       .distinct
                       .includes(:owner, :stage, :proposals, :sales_orders, :contracts, :activities)
                       .order(updated_at: :desc)

      activity_scope = visible_to_current_user(crm_scope.jrc_crm_activities, owner_column: :user_id)
      activities = activity_scope
                            .where(contact_id: contact.id)
                            .or(activity_scope.where(deal_id: deals.reorder(nil).select(:id)))
                            .includes(:user, :deal)
                            .order(created_at: :desc)
                            .limit(30)

      deal_ids = deals.reorder(nil).select(:id)
      orders_scope = visible_to_current_user(crm_scope.jrc_crm_sales_orders)
      orders = orders_scope.where(contact_id: contact.id).or(orders_scope.where(deal_id: deal_ids))
                           .includes(:deal).order(created_at: :desc)
      contracts_scope = visible_to_current_user(crm_scope.jrc_crm_contracts)
      contracts = contracts_scope.where(contact_id: contact.id).or(contracts_scope.where(deal_id: deal_ids))
                                 .includes(:deal).order(created_at: :desc)
      @visible_order_ids = orders.map(&:id)
      @visible_contract_ids = contracts.map(&:id)
      @visible_proposal_ids = visible_to_current_user(crm_scope.jrc_crm_proposals).where(deal_id: deal_ids).pluck(:id)

      open_deals = deals.select(&:open?)
      next_activity = deals.filter_map(&:next_activity).min_by(&:due_at)
      last_activity_at = ([contact.try(:last_activity_at)] + deals.map(&:last_activity_at) + activities.map(&:created_at)).compact.max

      render json: {
        profile: {
          id: contact.id,
          name: contact.name,
          email: contact.email,
          phone_number: contact.phone_number,
          company: contact.try(:company)&.name,
          created_at: contact.created_at,
          last_activity_at: last_activity_at
        },
        metrics: {
          deals: deals.size,
          open_deals: open_deals.size,
          won_deals: deals.count(&:won?),
          pipeline_cents: open_deals.sum(&:value_cents),
          proposals: @visible_proposal_ids.size,
          orders: orders.size,
          contracts: contracts.size,
          next_activity: next_activity && {
            id: next_activity.id,
            title: next_activity.title,
            due_at: next_activity.due_at
          }
        },
        deals: deals.map { |deal| serialize_deal(deal) },
        orders: orders.map { |order| { id: order.id, number: order.order_number, status: order.status,
          total_cents: order.total_cents, deal: order.deal && { id: order.deal.id, title: order.deal.title } } },
        contracts: contracts.map { |contract| { id: contract.id, number: contract.contract_number, status: contract.status,
          monthly_cents: contract.monthly_cents, deal: contract.deal && { id: contract.deal.id, title: contract.deal.title } } },
        timeline: activities.map { |activity| serialize_activity(activity) }
      }
    end

    private

    def serialize_deal(deal)
      {
        id: deal.id,
        title: deal.title,
        status: deal.status,
        value_cents: deal.value_cents,
        stage: deal.stage&.name,
        owner: deal.owner&.name,
        updated_at: deal.updated_at,
        next_activity: deal.next_activity && {
          id: deal.next_activity.id,
          title: deal.next_activity.title,
          due_at: deal.next_activity.due_at
        },
        proposals: deal.proposals.where(id: @visible_proposal_ids).order(created_at: :desc).map do |proposal|
          { id: proposal.id, number: proposal.proposal_number, status: proposal.status, title: proposal.title }
        end,
        orders: deal.sales_orders.where(id: @visible_order_ids).order(created_at: :desc).map do |order|
          { id: order.id, number: order.order_number, status: order.status, total_cents: order.total_cents }
        end,
        contracts: deal.contracts.where(id: @visible_contract_ids).order(created_at: :desc).map do |contract|
          { id: contract.id, number: contract.contract_number, status: contract.status, monthly_cents: contract.monthly_cents }
        end
      }
    end

    def serialize_activity(activity)
      {
        id: activity.id,
        type: activity.activity_type,
        title: activity.title,
        description: activity.description,
        status: activity.status,
        due_at: activity.due_at,
        completed_at: activity.completed_at,
        created_at: activity.created_at,
        user: activity.user&.name,
        deal: activity.deal && { id: activity.deal.id, title: activity.deal.title }
      }
    end
  end
end

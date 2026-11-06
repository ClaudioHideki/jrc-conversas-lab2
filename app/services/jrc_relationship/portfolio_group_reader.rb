class JrcRelationship::PortfolioGroupReader
  def initialize(context)
    @account_id = context.account.id
    @actor_id = context.user.id
  end

  def index(page: 1, query: '', status: 'active')
    with_authority do |context, capabilities|
      raise ArgumentError, 'Invalid portfolio status' unless %w[active archived all].include?(status)

      rows = JrcRelationship::PortfolioGroupScope.resolve(context)
      rows = rows.where(status: status) unless status == 'all'
      rows = rows.where('name ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(query.to_s.first(100))}%") if query.present?
      selected, meta = page_rows(rows.order(:name, :id).includes(:owner, :team, :business_unit, :segment), page)
      counts = customer_counts(context, selected.map(&:id))
      capabilities = record_capabilities(context, selected.map(&:id), capabilities)
      { payload: selected.map { |row| present(row, counts, capabilities) }, meta: meta }
    end
  end

  def show(id)
    with_authority do |context, capabilities|
      group = JrcRelationship::PortfolioGroupScope.resolve(context).find(id)
      capabilities = record_capabilities(context, [group.id], capabilities)
      present(group, customer_counts(context, [group.id]), capabilities)
    end
  end

  def customers(id, page: 1)
    with_authority do |context|
      group = JrcRelationship::PortfolioGroupScope.resolve(context).find(id)
      links = group.customer_links.where(account_id: context.account.id, active: true)
      rows = context.assignments.where(id: links.select(:assignment_id)).includes(:company, :contact, :owner).order(:id)
      selected, meta = page_rows(rows, page)
      { payload: selected.map do |row|
        { id: row.id, name: row.label, status: row.status, owner: row.owner && { id: row.owner_id, name: row.owner.name },
          business_unit_id: row.business_unit_id, customer_360: JrcRelationship::RecordPresentation.customer_route(row) }
      end, meta: meta }
    end
  end

  private

  def with_authority
    JrcRelationship::PortfolioGroup.transaction do
      JrcRelationship::BatchReviewAuthority.new(account_id: @account_id, actor_id: @actor_id, write: false).call do |context|
        capabilities = { 'can_manage' => context.policy.manage? && context.policy.team?, 'can_configure' => context.policy.configure? }
        yield context, capabilities
      end
    end
  end

  def page_rows(rows, page)
    number = Integer(page.to_s, 10).clamp(1, 10_000)
    [rows.limit(25).offset((number - 1) * 25).to_a, { page: number, per_page: 25, total: rows.count }]
  end

  def customer_counts(context, ids)
    links = JrcRelationship::PortfolioGroupAssignment.where(account_id: context.account.id, portfolio_group_id: ids, active: true)
    { all: links.group(:portfolio_group_id).count,
      visible: links.where(assignment_id: context.assignments.select(:id)).group(:portfolio_group_id).count }
  end

  def present(group, counts, capabilities)
    total = counts[:all].fetch(group.id, 0)
    visible = counts[:visible].fetch(group.id, 0)
    group.attributes.slice('id', 'name', 'objective', 'visibility', 'status', 'owner_id', 'team_id', 'business_unit_id', 'segment_id', 'goals')
         .merge(reference_names(group)).merge('version' => group.lock_version,
                                              'customer_count' => visible == total ? total : nil,
                                              'visible_customer_count' => visible, 'access_limited' => visible != total,
                                              'can_manage' => capabilities.fetch('editable_ids').include?(group.id),
                                              'can_configure' => capabilities.fetch('editable_ids').include?(group.id) &&
                                                capabilities.fetch('can_configure'))
  end

  def reference_names(group)
    { 'owner_name' => group.owner.name, 'team_name' => group.team&.name,
      'business_unit_name' => group.business_unit&.name, 'segment_name' => group.segment&.name }
  end

  def record_capabilities(context, ids, capabilities)
    capabilities.merge('editable_ids' => JrcRelationship::PortfolioGroupScope.writable(context).where(id: ids).pluck(:id))
  end
end

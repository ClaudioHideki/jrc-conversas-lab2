# Only the authenticated actor's operational metadata; never frozen audiences,
# customer names, group labels, reasons or snapshots. Details keep native gates.
class JrcRelationship::ReviewedBatchInventory
  STATES = %w[previewed running completed canceled attention].freeze
  ITEM_STATES = %w[pending applied failed canceled].freeze

  def initialize(context)
    @context = context
    @authority = JrcRelationship::BatchReviewAuthority.new(account_id: context.account.id, actor_id: context.user.id)
  end

  def index(page: 1, per_page: 25, status: 'all', portfolio_group_id: nil)
    number = Integer(page.to_s, 10).clamp(1, 10_000)
    size = Integer(per_page.to_s, 10).clamp(1, 50)
    raise ArgumentError, 'Invalid reviewed operation status' unless (%w[all pending] + STATES).include?(status)

    JrcRelationship::BatchReview.transaction do
      @authority.call do |context|
        rows = filtered_owned(context, status, portfolio_group_id)
        inventory_page(rows, number, size)
      end
    end
  end

  def cancel_pending(id, expected_revision:, reason:)
    raise ArgumentError, 'Provide a bounded cancellation reason' unless reason.is_a?(String) && reason.strip.length.between?(1, 4000)

    JrcRelationship::ReviewedBatchCancellation.new(@context).call(id, expected_revision: expected_revision, reason: reason.strip) do |review|
      row = { id: review.id, state: review.state, revision: review.revision, operation: review.inputs.fetch('operation'),
              created_at: review.created_at, updated_at: review.updated_at }
      row.merge(counts: item_counts(review.id, counts_for([review.id])), can_cancel_pending: review.state.in?(%w[previewed running]))
    end
  end

  private

  def owned(context)
    JrcRelationship::BatchReview.where(account_id: context.account.id, actor_id: context.user.id)
  end

  def filtered_owned(context, status, portfolio_group_id)
    rows = owned(context)
    rows = rows.where(state: status == 'pending' ? %w[previewed running] : status) unless status == 'all'
    group_id = JrcRelationship::PortfolioOwnerInput.parse(portfolio_group_id)
    group_id ? rows.where("inputs ->> 'portfolio_group_id' = ?", group_id.to_s) : rows
  end

  def inventory_page(rows, number, size)
    total = rows.count
    selected = rows.order(id: :desc).offset((number - 1) * size).limit(size).lock('FOR SHARE NOWAIT')
                   .select(:id, :state, :revision, :created_at, :updated_at, Arel.sql("inputs ->> 'operation' AS operation_kind")).to_a
    counts = counts_for(selected.map(&:id))
    { payload: selected.map { |review| present(review, counts) }, meta: { page: number, per_page: size, total: total } }
  end

  def counts_for(ids)
    JrcRelationship::BatchItem.where(account_id: @context.account.id, batch_review_id: ids).group(:batch_review_id, :state).count
  end

  def item_counts(id, counts)
    result = ITEM_STATES.index_with { |state| counts.fetch([id, state], 0) }
    result.merge('total' => result.values.sum)
  end

  def present(review, counts)
    { id: review.id, revision: review.revision, state: review.state, operation: review[:operation_kind],
      created_at: review.created_at, updated_at: review.updated_at, counts: item_counts(review.id, counts),
      can_cancel_pending: review.state.in?(%w[previewed running]) }
  end
end

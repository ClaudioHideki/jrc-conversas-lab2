# Read-only projection of the existing immutable snapshots. Product history
# never borrows another viewer's evidence or creates a second scoring registry.
class JrcRelationship::ProductHealthHistory
  FIELDS = %w[score band factors coverage_weight calculation_weight missing_factor_policy blocked config_scope_key config_version raw_band
              hysteresis].freeze

  def initialize(context)
    @member = context.member
  end

  def call(assignment_id:, product_id:, page: 1, per_page: 10)
    product, number, size = pagination(product_id, page, per_page)
    context = JrcRelationship::Context.new(@member)
    rows = scope(context, assignment_id, product)
    selected = rows.order(calculated_at: :desc, id: :desc).offset((number - 1) * size).limit(size + 1).to_a
    payload = present(selected, product).first(size)
    total = reauthorize!(context, assignment_id, product, selected)
    { payload: payload, meta: { page: number, per_page: size, total: total }, product_id: product }
  end

  private

  def pagination(product_id, page, per_page)
    product, number, size = [product_id, page, per_page].map { |value| Integer(value.to_s, 10) }
    raise ArgumentError, 'Invalid product history pagination' unless product.positive? && number.between?(1, 10_000) && size.between?(1, 50)

    [product, number, size]
  end

  def reauthorize!(original, assignment_id, product, selected)
    current = JrcRelationship::Context.new(@member)
    visible = scope(current, assignment_id, product)
    unless current.access_signature == original.access_signature && visible.where(id: selected.map(&:id)).count == selected.size
      raise Pundit::NotAuthorizedError
    end

    visible.count
  end

  def scope(context, assignment_id, product)
    assignment = context.assignment(assignment_id)
    rows = JrcRelationship::HealthSnapshot.where(account_id: context.account.id, assignment_id: assignment.id, viewer_id: context.user.id,
                                                 access_signature: context.access_signature)
                                          .where("jsonb_typeof(signals -> 'product_health' -> ?) = 'object'", product.to_s)
    JrcRelationship::SnapshotAccess.scope(context, rows)
  end

  def present(rows, product)
    rows.each_with_index.map do |snapshot, index|
      health = snapshot.signals.fetch('product_health').fetch(product.to_s).slice(*FIELDS)
      previous = rows[index + 1]&.signals&.dig('product_health', product.to_s)&.slice(*FIELDS)
      { id: snapshot.id, calculated_at: snapshot.calculated_at, health: health,
        change: JrcRelationship::HealthChange.call(previous: previous&.symbolize_keys, current: health.symbolize_keys) }
    end
  end
end

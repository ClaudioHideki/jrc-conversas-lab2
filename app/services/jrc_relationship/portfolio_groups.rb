# Coordinates metadata and links only. No customer owner, team, source record,
# capacity input or source-module permission is changed by group membership.
class JrcRelationship::PortfolioGroups
  FIELDS = %w[name objective owner_id team_id business_unit_id segment_id visibility status goals].freeze
  SCOPE_FIELDS = %w[visibility team_id business_unit_id].freeze

  def initialize(context)
    @account_id = context.account.id
    @actor_id = context.user.id
  end

  def create!(attributes)
    with_authority do |context|
      attrs = normalize(attributes)
      attrs['owner_id'] = context.user.id unless attrs.key?('owner_id')
      group = JrcRelationship::PortfolioGroup.new(attrs.merge('account_id' => context.account.id))
      verify_sharing!(context, group)
      group.save!
      verify_source_and_destination!(context, group)
      context.audit!(group, action: 'portfolio_group_created', after: group.attributes.slice(*FIELDS))
      receipt(group)
    end
  end

  def update!(id, attributes:, expected_version:, reason:)
    validate_reason!(reason)
    with_authority do |context|
      group = locked_group(context, id, expected_version)
      before = group.attributes.slice(*FIELDS)
      group.assign_attributes(normalize(attributes))
      verify_sharing!(context, group)
      verify_unit_members!(group)
      JrcRelationship::PortfolioGroupConfiguration.before_archive!(group)
      group.save!
      verify_source_and_destination!(context, group)
      context.audit!(group, action: 'portfolio_group_updated', before: before,
                            after: group.attributes.slice(*FIELDS).merge('reason' => reason.strip))
      receipt(group)
    end
  end

  def set_customers!(id, ids:, active:, expected_version:, reason:)
    validate_reason!(reason)
    raise ArgumentError, 'Use an explicit customer membership boolean' unless [true, false].include?(active)

    selected = customer_ids(ids)
    with_authority do |context|
      group = locked_group(context, id, expected_version)
      raise ArgumentError, 'Archived portfolios cannot change their customer links' unless group.status == 'active'

      before, after = customer_link_changes(context, group, selected, active)
      verify_source_and_destination!(context, group)
      if before != after
        # Association-only changes still advance the native optimistic revision.
        group.lock_version_will_change!
        group.save!
        context.audit!(group, action: 'portfolio_group_customers_updated', before: { customers: before },
                              after: { customers: after, reason: reason.strip })
      end
      receipt(group)
    end
  end

  private

  def with_authority
    JrcRelationship::PortfolioGroup.transaction do
      authority = JrcRelationship::BatchReviewAuthority.new(account_id: @account_id, actor_id: @actor_id)
      authority.call do |context|
        raise Pundit::NotAuthorizedError unless context.policy.team?

        yield context
      end
    end
  end

  def normalize(attributes)
    attrs = attributes.to_h.stringify_keys
    raise ArgumentError, 'Unsupported portfolio fields' unless (attrs.keys - FIELDS).empty?

    %w[owner_id team_id business_unit_id segment_id].each do |key|
      attrs[key] = JrcRelationship::PortfolioOwnerInput.parse(attrs[key]) if attrs.key?(key)
    end
    validate_text!(attrs)
    attrs['name'] = attrs['name'].strip if attrs.key?('name')
    attrs
  end

  def customer_ids(ids)
    raise ArgumentError, 'Choose1to50 existing customer allocations' unless ids.is_a?(Array) && ids.size.between?(1, 50)

    values = ids.map { |id| JrcRelationship::PortfolioOwnerInput.parse(id) }
    raise ArgumentError, 'Choose unique positive allocation IDs' if values.any?(&:nil?) || values.uniq.size != values.size

    values.sort
  end

  def validate_text!(attrs)
    %w[name objective].each do |key|
      raise ArgumentError, 'Portfolio name and objective must be text' if attrs.key?(key) && !attrs[key].is_a?(String)
    end
  end

  def customer_link_changes(context, group, selected, active)
    rows = context.assignments.where(id: selected).order(:id).to_a
    raise ActiveRecord::RecordNotFound unless rows.size == selected.size

    JrcRelationship::PortfolioGroupConfiguration.before_unlink!(group, selected) unless active

    links = group.customer_links.where(assignment_id: selected).order(:assignment_id)
    before = links.pluck(:assignment_id, :active)
    persist_customer_links(group, rows, active)
    existing = before.select { |_, enabled| enabled }.map(&:first)
    JrcRelationship::PortfolioGroupConfiguration.admit!(group, rows.reject { |row| existing.include?(row.id) }) if active
    [before, links.pluck(:assignment_id, :active)]
  end

  def persist_customer_links(group, rows, active)
    rows.each do |assignment|
      link = group.customer_links.find_or_initialize_by(account_id: group.account_id, assignment_id: assignment.id)
      next if !active && link.new_record?

      link.update!(active: active)
    end
  end

  def locked_group(context, id, version)
    raise ArgumentError, 'A whole-number portfolio revision is required' unless version.is_a?(Integer) && version >= 0

    group = JrcRelationship::PortfolioGroupScope.writable(context).lock('FOR UPDATE NOWAIT').find(id)
    raise ActiveRecord::StaleObjectError.new(group, 'update') unless group.lock_version == version

    group
  end

  def verify_sharing!(context, group)
    changed = group.new_record? ? group.visibility != 'private' : SCOPE_FIELDS.any? { |field| group.will_save_change_to_attribute?(field) }
    raise Pundit::NotAuthorizedError if changed && !context.policy.configure?

    verify_group_team!(context, group)
    verify_group_owner!(context, group)
  end

  def verify_group_team!(context, group)
    return unless group.team_id && (group.new_record? || group.will_save_change_to_team_id?)

    verify_team!(context, group)
  end

  def verify_group_owner!(context, group)
    return unless group.owner_id && (group.new_record? || group.will_save_change_to_owner_id?)

    context.assignable_users.find(group.owner_id)
  end

  def verify_unit_members!(group)
    return unless group.business_unit_id

    assignments = JrcRelationship::Assignment.where(account_id: @account_id, id: group.customer_links.where(active: true).select(:assignment_id))
    mismatch = assignments.where.not(business_unit_id: group.business_unit_id).or(assignments.where(business_unit_id: nil))
    raise ArgumentError, 'Review customer unit links before changing the portfolio unit' if mismatch.exists?
  end

  def verify_source_and_destination!(context, group)
    raise ActiveRecord::RecordNotFound unless JrcRelationship::PortfolioGroupScope.organizational(context).exists?(id: group.id)
    return unless group.status == 'active'

    owner = JrcRelationship::BatchReviewAuthority.new(account_id: @account_id, actor_id: group.owner_id, write: false)
    owner.call do |target|
      raise Pundit::NotAuthorizedError unless target.policy.manage?
      raise Pundit::NotAuthorizedError unless JrcRelationship::PortfolioGroupScope.resolve(target).exists?(id: group.id)

      links = group.customer_links.where(active: true)
      raise Pundit::NotAuthorizedError if links.where.not(assignment_id: target.assignments.select(:id)).exists?
    end
  end

  def validate_reason!(reason)
    raise ArgumentError, 'Provide a bounded change reason' unless reason.is_a?(String) && reason.strip.length.between?(1, 4000)
  end

  def verify_team!(context, group)
    teams = context.account.teams
    teams = teams.joins(:team_members).where(team_members: { user_id: context.user.id }) unless context.policy.admin?
    teams.find(group.team_id)
  end

  def receipt(group)
    { id: group.id, version: group.lock_version }
  end
end

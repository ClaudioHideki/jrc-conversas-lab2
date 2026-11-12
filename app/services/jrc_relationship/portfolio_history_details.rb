class JrcRelationship::PortfolioHistoryDetails
  ACTIONS = %w[portfolio_group_created portfolio_group_updated portfolio_group_customers_updated
               configuration_versioned configuration_restored].freeze
  FIELDS = (JrcRelationship::PortfolioGroups::FIELDS + ['customers']).freeze

  def self.event_digest(event)
    JrcRelationship::PortfolioHistoryBoundary.digest(
      'id' => event.id, 'account_id' => event.account_id, 'actor_type' => event.actor_type, 'actor_id' => event.actor_id,
      'resource_type' => event.resource_type, 'resource_id' => event.resource_id,
      'from' => event.from_value, 'to' => event.to_value, 'metadata' => event.metadata
    )
  end

  # Capture only new events in their own native mutation transaction. No legacy
  # audit row is backfilled with the current scope as if it were its old scope.
  def self.capture!(event, resource:)
    return unless ACTIONS.include?(event.metadata.to_h['action'])
    group = if resource.is_a?(JrcRelationship::PortfolioGroup)
              resource
            elsif resource.is_a?(JrcRelationship::Configuration) && resource.scope_key.match?(/\Aportfolio:[1-9][0-9]*\z/)
              JrcRelationship::PortfolioGroup.find_by!(account_id: resource.account_id, id: resource.scope_key.split(':').last)
            end
    return unless group

    before = event.from_value.is_a?(Hash) ? event.from_value : {}
    after = event.to_value.is_a?(Hash) ? event.to_value : {}
    boundary = group.attributes.slice(*JrcRelationship::PortfolioHistoryBoundary::BOUNDARY_FIELDS)
    boundaries = [boundary]
    if resource.is_a?(JrcRelationship::PortfolioGroup) && event.metadata['action'] == 'portfolio_group_updated'
      boundaries.unshift(boundary.merge(before.slice(*JrcRelationship::PortfolioHistoryBoundary::BOUNDARY_FIELDS)))
    end
    selected = [before['customers'], after['customers']].select { |value| value.is_a?(Array) }.flatten(1).filter_map do |row|
      row.first if row.is_a?(Array) && row.first.is_a?(Integer)
    end
    ids = (group.customer_links.where(active: true).pluck(:assignment_id) + selected).uniq.sort
    fields = JrcRelationship::PortfolioHistoryBoundary::ORIGIN_FIELDS
    origins = JrcRelationship::Assignment.where(account_id: group.account_id, id: ids).order(:id).pluck(*fields)
                                        .map { |values| fields.zip(values).to_h }
    # Failure aborts the originating operation rather than publishing a proof
    # that silently ignores an unresolved historic source.
    raise ActiveRecord::RecordNotFound, 'Cannot capture unresolved portfolio origins' unless origins.size == ids.size

    kind = resource.is_a?(JrcRelationship::Configuration) ? 'rules' : 'group'
    values = ->(value) do
      if kind == 'rules'
        rules = value['rules']
        if !rules.is_a?(Hash) && value['version'].is_a?(Integer)
          rules = resource.versions.find_by(account_id: group.account_id, version: value['version'])&.rules
        end
        # The complete event remains digest-bound; this detail projection does
        # not expose explicit local user grants stored in configuration versions.
        { 'version' => value['version'], 'rules' => rules.to_h.slice(*JrcRelationship::PortfolioHistoryBoundary::RULE_FIELDS) }
      else
        value.slice(*FIELDS)
      end
    end
    snapshot = { 'version' => 1, 'account_id' => group.account_id, 'group_id' => group.id, 'kind' => kind,
                 'event_digest' => event_digest(event), 'boundaries' => boundaries.uniq, 'origins' => origins, 'resolved' => true,
                 'before' => values.call(before), 'after' => values.call(after), 'reason' => after['reason'] }
    JrcRelationship::PortfolioHistoryReceipt.create!(account_id: group.account_id, portfolio_group: group, audit_event: event,
      snapshot: snapshot, digest: JrcRelationship::PortfolioHistoryBoundary.digest(snapshot), created_at: Time.current)
  end

  def initialize(context)
    @account_id, @actor_id = context.account.id, context.user.id
  end

  def call(group_id:, event_id:)
    result = nil
    JrcRelationship::PortfolioGroup.transaction do
      JrcRelationship::BatchReviewAuthority.new(account_id: @account_id, actor_id: @actor_id, write: false).call do |context|
        group = JrcRelationship::PortfolioGroupAccess.complete_management!(context, group_id)
        event = events(context, group).find(event_id)
        receipt = JrcRelationship::PortfolioHistoryReceipt.find_by(account_id: @account_id, portfolio_group_id: group.id, audit_event_id: event.id)
        result = { projection: 'scoped_historical_detail', group_id: group.id, event_id: event.id,
                   available: false, reason: 'original_scope_unavailable' }
        if receipt
          snapshot = receipt.snapshot
          raise Pundit::NotAuthorizedError unless allowed?(context, group, event, receipt)
          result = { projection: 'scoped_historical_detail', group_id: group.id, event_id: event.id, available: true,
                     before: snapshot['before'], after: snapshot['after'], reason: snapshot['reason'],
                     at: event.created_at.iso8601(6), digest: receipt.digest, references: references(context, snapshot) }
          # Source/customer ownership can change independently while a read runs.
          # Reload the current policy and enforce it again before returning bytes.
          fresh = JrcRelationship::Context.new(context.member)
          JrcRelationship::PortfolioGroupAccess.complete_management!(fresh, group.id)
          raise Pundit::NotAuthorizedError unless fresh.user.reload.active_for_authentication? && allowed?(fresh, group, event, receipt)
        end
      end
    end
    result
  end

  private

  def events(context, group)
    base = JrcCrm::AuditEvent.where(account_id: @account_id, event_type: 'relationship_updated')
    rows = base.where(resource_type: group.class.name, resource_id: group.id)
    if context.policy.configure?
      configuration = JrcRelationship::PortfolioGroupConfiguration.for(group)
      rows = rows.or(base.where(resource_type: configuration.class.name, resource_id: configuration.id)) if configuration
    end
    rows
  end

  def allowed?(context, group, event, receipt)
    teams = TeamMember.where(user_id: context.user.id, team_id: context.account.teams.select(:id)).pluck(:team_id)
    coverage = JrcCrm::CorporateCoverage.new(account: context.account, user: context.user)
    unit_allowed = lambda do |id|
      if coverage.configured?
        id ? coverage.unit_allowed?(id) : coverage.group?
      else
        id.nil? || context.account.jrc_crm_business_units.exists?(id: id)
      end
    end
    validator = JrcRelationship::PortfolioHistoryBoundary.new(account_id: @account_id, group_id: group.id,
      actor_id: context.user.id, admin: context.policy.admin?, configure: context.policy.configure?, team_ids: teams,
      unit_allowed: unit_allowed, origins_allowed: ->(origins) { origins_allowed?(context, origins) },
      references_allowed: ->(snapshot) { references_allowed?(context, snapshot) })
    validator.allowed?(receipt.snapshot, snapshot_digest: receipt.digest, event_digest: self.class.event_digest(event))
  end

  def origins_allowed?(context, origins)
    fields = JrcRelationship::PortfolioHistoryBoundary::ORIGIN_FIELDS
    origins.each_slice(250).all? do |batch|
      current = context.assignments.where(id: batch.map { |row| row['id'] }).order(:id).pluck(*fields).map { |values| fields.zip(values).to_h }
      current == batch.sort_by { |row| row['id'] }
    end
  end

  def referenced_ids(snapshot, field)
    ids = snapshot['boundaries'].filter_map { |row| row[field] }
    if field == 'owner_id'
      %w[before after].each do |position|
        capacities = snapshot.dig(position, 'rules', 'portfolio_capacity_limits')
        ids.concat(capacities.filter_map { |row| row['user_id'] }) if capacities.is_a?(Array)
      end
    end
    ids.uniq
  end

  def references_allowed?(context, snapshot)
    user_ids = referenced_ids(snapshot, 'owner_id')
    team_ids = referenced_ids(snapshot, 'team_id')
    segment_ids = referenced_ids(snapshot, 'segment_id')
    context.assignable_users.where(id: user_ids).distinct.count == user_ids.size &&
      context.account.teams.where(id: team_ids).count == team_ids.size &&
      JrcCustomers::Taxonomy.where(account_id: @account_id, kind: 'segment', id: segment_ids).count == segment_ids.size
  end

  def references(context, snapshot)
    { users: context.assignable_users.where(id: referenced_ids(snapshot, 'owner_id')).pluck(:id, :name).to_h,
      teams: context.account.teams.where(id: referenced_ids(snapshot, 'team_id')).pluck(:id, :name).to_h,
      units: context.account.jrc_crm_business_units.where(id: referenced_ids(snapshot, 'business_unit_id')).pluck(:id, :name).to_h,
      segments: JrcCustomers::Taxonomy.where(account_id: @account_id, kind: 'segment', id: referenced_ids(snapshot, 'segment_id')).pluck(:id, :name).to_h }
  end
end

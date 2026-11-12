# Company IDs and native allocation IDs are deliberately separate throughout.
class JrcRelationship::MasterAllocationSources
  def initialize(context)
    @context = context
  end

  def companies
    JrcCrm::CorporateCoverage.new(account: @context.account, user: @context.user).companies(@context.account.master_companies)
  end

  def records(inputs, lock: false)
    customers = selected_companies(inputs.fetch('ids'), lock)
    roots = existing_roots(inputs.fetch('ids'), lock)
    proposals = inputs.fetch('creations').index_by { |row| row.fetch('company_id') }
    customers.map do |company|
      roots[company.id] || prepare(proposals.fetch(company.id) do
        raise ArgumentError, 'Missing native allocation proposal'
      end)
    end
  end

  def pin(record)
    company = record.company
    allocation = record.attributes.slice('owner_id', 'team_id', 'business_unit_id', 'status')
    allocation['settings'] = record.settings.slice(*JrcRelationship::AssignmentCreation::SETTINGS)
    if record.persisted?
      return JrcRelationship::BatchReviewPlan.new(@context).row_snapshot(record)
                                             .merge('company_id' => company.id, 'mode' => 'reuse', 'allocation' => allocation)
    end

    attrs = record.attributes.slice('account_id', 'company_id', 'owner_id', 'team_id', 'business_unit_id', 'status')
    settings = record.settings.except('eligibility_exception')
    exception = record.settings['eligibility_exception']&.slice('reason', 'approved_by_id')
    { 'company_id' => company.id, 'assignment_id' => nil, 'mode' => 'create', 'label' => company.name, 'allocation' => allocation,
      'digest' => JrcRelationship::PlaybookFlowReference.digest([attrs, settings, exception, company.attributes]) }
  end

  def authorize_read!(review)
    ids = review.inputs.fetch('ids')
    raise ActiveRecord::RecordNotFound unless companies.where(id: ids).count == ids.size

    JrcRelationship::PortfolioGroupAccess.complete_management!(@context, review.inputs.fetch('portfolio_group_id'))
    original = review.snapshot.fetch('rows').filter_map { |row| row['assignment_id'] }
    applied = review.items.where(state: 'applied').pluck(:assignment_id)
    expected = (original + applied).uniq
    raise ActiveRecord::RecordNotFound unless @context.assignments.where(id: expected).count == expected.size
  end

  def authority_pin(records, group)
    access = JrcRelationship::AssignmentProposalAccess.new(@context)
    { 'configurations' => configuration_digest(records, group),
      'destinations' => records.map { |record| [record.company_id, access.call(record)] },
      'group_owner_access_signature' => group_owner_signature(records, group, access) }
  end

  private

  def selected_companies(ids, lock)
    directory = companies.where(id: ids).order(:id)
    directory = directory.lock('FOR SHARE NOWAIT') if lock
    customers = directory.to_a
    raise ActiveRecord::RecordNotFound unless customers.size == ids.size

    customers
  end

  def existing_roots(ids, lock)
    scope = JrcRelationship::Assignment.where(account_id: @context.account.id, company_id: ids)
    scope = scope.lock('FOR UPDATE NOWAIT') if lock
    existing = scope.to_a
    raise ActiveRecord::RecordNotFound unless existing.size == @context.assignments.where(id: existing.map(&:id)).count

    existing.index_by(&:company_id)
  end

  def configuration_digest(records, group)
    sources = JrcRelationship::DistributionConfigurations.new(@context.account)
    configurations = records.flat_map { |record| sources.for(record) }
    configurations += JrcRelationship::Configuration.where(account: @context.account, scope_key: ['account', "portfolio:#{group.id}"]).to_a
    configs = configurations.uniq(&:scope_key).sort_by(&:scope_key).map { |row| row.attributes.slice('scope_key', 'version', 'weights', 'rules') }
    JrcRelationship::PortfolioGroupConfiguration.authorize_bindings!(@context, configs)
    JrcRelationship::PlaybookFlowReference.digest(configs)
  end

  def group_owner_signature(records, group, access)
    owner = JrcRelationship::BatchReviewAuthority.new(account_id: @context.account.id, actor_id: group.owner_id, write: false)
    owner.call do |target|
      raise Pundit::NotAuthorizedError unless target.policy.manage? && JrcRelationship::PortfolioGroupScope.resolve(target).exists?(id: group.id)
      raise Pundit::NotAuthorizedError unless records.all? { |record| access.visible_to?(target, record) }

      target.access_signature
    end
  end

  def prepare(proposal)
    JrcRelationship::AssignmentCreation.new(@context).preview(proposal.except('exception_reason'), exception_reason: proposal['exception_reason'])
  end
end

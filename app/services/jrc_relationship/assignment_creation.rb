# The native individual creation path, reusable by reviewed operations. Never
# creates a master customer or grants source visibility through supplied IDs.
class JrcRelationship::AssignmentCreation
  FIELDS = %w[company_id contact_id owner_id team_id business_unit_id settings].freeze
  SETTINGS = %w[segment_id product_id complexity capacity_workload].freeze

  def initialize(context)
    @account_id = context.account.id
    @actor_id = context.user.id
  end

  def call(attributes, exception_reason: nil)
    attrs = input(attributes)
    JrcRelationship::Assignment.transaction do
      authority = JrcRelationship::BatchReviewAuthority.new(account_id: @account_id, actor_id: @actor_id)
      authority.call do |context|
        raise Pundit::NotAuthorizedError unless context.policy.team?

        persist!(context, normalize(context, attrs), exception_reason)
      end
    end
  end

  # Native validations and source policies without INSERT, temporary records or
  # sequence consumption. Execution still rechecks through the native writer.
  def preview(attributes, exception_reason: nil)
    attrs = input(attributes)
    JrcRelationship::Assignment.transaction do
      JrcRelationship::BatchReviewAuthority.new(account_id: @account_id, actor_id: @actor_id).call do |context|
        raise Pundit::NotAuthorizedError unless context.policy.team?

        record = prepare(context, normalize(context, attrs), exception_reason)
        record.validate!
        JrcRelationship::AssignmentProposalAccess.new(context).call(record)
        record
      end
    end
  end

  private

  def input(attributes)
    attrs = attributes.to_h.deep_stringify_keys
    raise ArgumentError, 'Unsupported allocation fields' unless (attrs.keys - FIELDS).empty?

    validate_settings!(attrs)
    attrs
  end

  def validate_settings!(attrs)
    return unless attrs.key?('settings')

    settings = attrs['settings']
    raise ArgumentError, 'Unsupported allocation settings' unless settings.is_a?(Hash) && (settings.keys - SETTINGS).empty?
  end

  def normalize(context, attributes)
    attrs = attributes.deep_dup
    attrs['owner_id'] = JrcRelationship::PortfolioOwnerInput.parse(attrs['owner_id']) if attrs.key?('owner_id')
    if attrs['contact_id'].present?
      contact = JrcOperations::Access.contact!(context.member, attrs['contact_id'])
      if contact.company_id
        attrs['company_id'] = contact.company_id
        attrs['contact_id'] = nil
      end
    end
    context.assignable_users.find(attrs['owner_id']) if attrs['owner_id'].present?
    attrs
  end

  def persist!(context, attrs, exception_reason)
    record = prepare(context, attrs, exception_reason)
    record.save!
    context.assignment(record.id)
    JrcRelationship::DistributionPolicyBinding.new(context).call([record], owner_id: record.owner_id) if record.owner_id
    context.audit!(record, after: attrs, action: 'assignment_created')
    if record.settings['eligibility_exception']
      context.audit!(record, after: record.settings['eligibility_exception'], action: 'eligibility_exception_approved')
    end
    record
  end

  def prepare(context, attrs, exception_reason)
    record = JrcRelationship::Assignment.new(attrs.merge('account_id' => context.account.id))
    record.status = 'onboarding' if context.configuration.effective_rules['handoff_acceptance_required']
    validate_eligibility!(context, record, exception_reason)
    record
  end

  def validate_eligibility!(context, record, exception_reason)
    return unless context.configuration.effective_rules['eligibility_mode'] == 'active_contract_product'

    reason = JrcRelationship::CommercialEligibility.reason(record.customer_context(context.member).contracts,
                                                           account: context.account, product_id: record.settings['product_id'])
    return unless reason

    valid_exception = exception_reason.is_a?(String) && exception_reason.strip.length.between?(1, 2000)
    raise ArgumentError, reason unless valid_exception

    record.settings = record.settings.merge('eligibility_exception' => eligibility_exception(context, exception_reason))
  end

  def eligibility_exception(context, reason)
    { 'reason' => reason.strip, 'approved_by_id' => context.user.id, 'approved_at' => Time.current.iso8601 }
  end
end

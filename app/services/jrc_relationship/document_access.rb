# Native document authority + current customer scope + independent local capabilities.
# Unclassified historical files require an explicit classification by a document manager.
class JrcRelationship::DocumentAccess
  ACTIONS = %w[view download upload replace manage].freeze

  def self.allowed?(context, document, action)
    return false unless ACTIONS.include?(action) && document.account_id == context.account.id
    assignment = context.assignments.find_by(id: document.assignment_id)
    return false unless assignment
    native = case action
             when 'view' then context.policy.documents_view?
             when 'download' then context.policy.documents_download?
             when 'upload' then context.policy.documents_upload?
             when 'replace' then context.policy.documents_replace?
             when 'manage' then context.policy.documents_manage?
             end
    return false unless native && JrcRelationship::LocalAccess.assignment_allowed?(context.member, assignment,
      "document_#{action}", document_category: document.category)
    classification = document.confidentiality
    if classification.nil?
      # Managers may classify metadata; an unclassified legacy file cannot be downloaded.
      return %w[view manage].include?(action) && context.policy.documents_manage?
    end
    return false unless %w[operational restricted].include?(classification)
    return true if classification == 'operational'
    context.policy.documents_restricted? && JrcRelationship::LocalAccess.assignment_allowed?(context.member, assignment,
      'document_restricted', document_category: document.category)
  end

  def self.authorize!(context, document, action)
    raise Pundit::NotAuthorizedError unless allowed?(context, document, action)
    document
  end

  def self.scope(context, relation)
    rows = relation
    unless context.policy.documents_manage?
      rows = rows.where.not(confidentiality: nil)
    end
    rows = rows.where(confidentiality: [nil, 'operational']) unless context.policy.documents_restricted?
    # Each configured scope is an additional restriction; no per-record SQL loop.
    configs = JrcRelationship::Configuration.where(account_id: context.account.id)
      .where("jsonb_exists(rules, ?)", JrcRelationship::LocalAccess::KEY)
    configs.each do |config|
      rule = config.rules[JrcRelationship::LocalAccess::KEY]
      next if rule.nil?

      JrcRelationship::LocalRoleRules.normalize!(rule)
      next unless rule['enabled']
      binding = JrcRelationship::LocalRoleRules.binding(rule, context.user.id)
      categories = binding ? binding['document_categories'] : []
      metadata = { user_id: context.user.id, action: 'document_view', owner_id: :metadata }
      permitted = JrcRelationship::LocalRoleRules.allowed?(rule, **metadata)
      scoped = permitted ? rows.where(category: categories) : rows.none
      restricted = JrcRelationship::LocalRoleRules.allowed?(rule, user_id: context.user.id,
        action: 'document_restricted', owner_id: :metadata)
      scoped = scoped.where(confidentiality: [nil, 'operational']) unless restricted
      if config.scope_key == 'account'
        rows = rows.where(id: scoped.select(:id))
      elsif config.scope_key.match?(/\Aportfolio:[1-9][0-9]*\z/)
        group_id = config.scope_key.split(':').last.to_i
        next unless JrcRelationship::PortfolioGroup.exists?(account_id: context.account.id, id: group_id, status: 'active')
        links = JrcRelationship::PortfolioGroupAssignment.where(account_id: context.account.id,
          portfolio_group_id: group_id, active: true).select(:assignment_id)
        denied = rows.where(assignment_id: links).where.not(id: scoped.select(:id))
        rows = rows.where.not(id: denied.select(:id))
      end
    end
    rows
  end
end

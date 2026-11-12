# Evaluate the exact native SQL policy on typed proposed attributes, without
# persisting a customer allocation or fabricating an allocation ID.
class JrcRelationship::AssignmentProposalAccess
  def initialize(context)
    @context = context
  end

  def call(record)
    raise ActiveRecord::RecordNotFound unless record.account_id == @context.account.id

    relation = proposed_relation(record)
    raise ActiveRecord::RecordNotFound unless JrcRelationship::AssignmentPolicy::Scope.new(@context.to_h, relation).resolve.exists?
    return {} unless record.owner_id

    authority = JrcRelationship::BatchReviewAuthority.new(account_id: @context.account.id, actor_id: record.owner_id, write: false)
    authority.call do |target|
      scope = JrcCrm::OrganizationalVisibility.new(account: target.account, user: target.user, relation: relation, include_company: false).call
      raise Pundit::NotAuthorizedError unless scope.exists?

      { 'owner_access_signature' => target.access_signature }
    end
  end

  def visible_to?(context, record)
    JrcRelationship::AssignmentPolicy::Scope.new(context.to_h, proposed_relation(record)).resolve.exists?
  end

  private

  def proposed_relation(record)
    json = JrcRelationship::Assignment.connection.quote(record.attributes.to_json)
    JrcRelationship::Assignment.from("jsonb_populate_record(NULL::jrc_relationship_assignments, #{json}::jsonb) AS jrc_relationship_assignments")
  end
end

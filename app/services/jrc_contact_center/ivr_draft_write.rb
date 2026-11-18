# frozen_string_literal: true

# Account authority lock precedes native unit and immutable draft locks.
class JrcContactCenter::IvrDraftWrite
  def initialize(context:)
    @context = context.slice(:account, :account_user, :user)
  end

  def call(input:, id: nil, unit_id: nil)
    JrcContactCenter::AuthorityTransaction.call(account: @context.fetch(:account), member: @context.fetch(:account_user)) do
      @scope = JrcContactCenter::IvrDraftAccess.new(context: @context)
      receipt = JrcContactCenter::IvrDraftVersion.find_by(account: @context.fetch(:account), request_id: input.request_id)
      next replay!(receipt, input, id, unit_id) if receipt

      draft = id ? @scope.relation.lock.find(id) : nil
      unit = @scope.access.units.lock('FOR NO KEY UPDATE').find(draft ? draft.unit_id : unit_id)
      @scope = JrcContactCenter::IvrDraftAccess.new(context: @context)
      @scope.access.units.find(unit.id)
      @scope.find!(draft.id) if draft
      write!(draft, unit, input)
    end
  end

  private

  def write!(draft, unit, input)
    previous = draft&.latest_version
    conflict! unless input.expected_revision == (previous&.revision || 0)
    validate_definition!(draft, unit, input, previous)
    draft ||= JrcContactCenter::IvrDraft.create!(account: @context.fetch(:account), unit: unit, scope_snapshot: {}).reload
    actor = { actor_account_user_id: @context.fetch(:account_user).id, actor_user_id: @context.fetch(:user).id }
    attributes = input.attributes.merge(actor).merge(account: @context.fetch(:account), ivr_draft: draft, revision: input.expected_revision + 1)
    version = JrcContactCenter::IvrDraftVersion.create!(attributes).reload
    JrcContactCenter::IvrDraftAudit.write!(draft, version, @scope.context)
    { draft: draft, version: version, latest_revision: version.revision, replayed: false }
  end

  def validate_definition!(draft, unit, input, previous)
    if input.status == 'archived'
      valid = previous && previous.name == input.name && previous.definition == input.definition
      raise JrcContactCenter::OperationError, 'ivr_archive_requires_unchanged_definition' unless valid
    else
      @scope.authorize_unchanged_scope!(draft, unit) if draft
      JrcContactCenter::IvrGraph.new(input.definition, access: @scope.access, unit_id: unit.id)
    end
  end

  def replay!(version, input, id, unit_id)
    draft = @scope.find!(version.ivr_draft_id)
    own = version.actor_account_user_id == @context.fetch(:account_user).id && version.actor_user_id == @context.fetch(:user).id
    raise Pundit::NotAuthorizedError unless own

    same_target = id ? draft.id.to_s == id.to_s : version.revision == 1 && draft.unit_id.to_s == unit_id.to_s
    conflict! unless same_target && input.matches?(version)
    { draft: draft, version: version, latest_revision: draft.latest_version.revision, replayed: true }
  end

  def conflict!
    raise JrcContactCenter::OperationError.new('stale_ivr_revision', status: :conflict)
  end
end

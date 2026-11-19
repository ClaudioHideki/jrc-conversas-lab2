# frozen_string_literal: true

class JrcContactCenter::AcwFormWrite
  def initialize(context:)
    @context = context.slice(:account, :account_user, :user)
  end

  def call(input:, id: nil)
    JrcContactCenter::AuthorityTransaction.call(account: @context.fetch(:account), member: @context.fetch(:account_user)) do
      @scope = JrcContactCenter::AcwFormAccess.new(context: @context)
      receipt = JrcContactCenter::AcwFormVersion.find_by(account: @context.fetch(:account), request_id: input.request_id)
      next replay!(receipt, input, id) if receipt

      form = @scope.relation.lock.find(id) if id
      write!(form, input)
    end
  end

  private

  def write!(form, input)
    previous = form&.latest_version
    conflict! unless input.expected_revision == (previous&.revision || 0)
    validate_archive!(previous, input)
    form ||= JrcContactCenter::AcwFormTemplate.create!(account: @context.fetch(:account), scope_snapshot: {}).reload
    actor = { actor_account_user_id: @context.fetch(:account_user).id, actor_user_id: @context.fetch(:user).id }
    attributes = input.attributes.merge(actor).merge(account: @context.fetch(:account), acw_form_template: form,
                                                     revision: input.expected_revision + 1)
    version = JrcContactCenter::AcwFormVersion.create!(attributes).reload
    JrcContactCenter::AcwFormAudit.write!(form, version, @scope.context)
    { form: form, version: version, latest_revision: version.revision, replayed: false }
  end

  def validate_archive!(previous, input)
    return unless input.status == 'archived'

    valid = previous && previous.name == input.name && previous.description == input.description && previous.definition == input.definition
    raise JrcContactCenter::OperationError, 'acw_form_archive_requires_unchanged_definition' unless valid
  end

  def replay!(version, input, id)
    form = @scope.find!(version.acw_form_template_id)
    own = version.actor_account_user_id == @context.fetch(:account_user).id && version.actor_user_id == @context.fetch(:user).id
    raise Pundit::NotAuthorizedError unless own

    same_target = id ? form.id.to_s == id.to_s : version.revision == 1
    conflict! unless same_target && input.matches?(version)
    { form: form, version: version, latest_revision: form.latest_version.revision, replayed: true }
  end

  def conflict!
    raise JrcContactCenter::OperationError.new('stale_acw_form_revision', status: :conflict)
  end
end

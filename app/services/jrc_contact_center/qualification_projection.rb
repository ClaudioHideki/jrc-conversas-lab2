# frozen_string_literal: true

# The ordinary native payload remains shared under the caller's origin policy; new private answers are own-only.
class JrcContactCenter::QualificationProjection
  def initialize(account:, member:)
    @account = account
    @member = member
  end

  def call(record)
    raise ActiveRecord::RecordNotFound unless record.account_id == @account.id

    forms = JrcContactCenter::QualificationForms.new(record)
    return legacy_payload(record) if record.account_user_id != @member.id && !forms.state

    JrcContactCenter::AuthorityTransaction.call(account: @account, member: @member) do
      context = { account: @account, account_user: @member, user: @member.user }
      allowed = @member.user.reload.active_for_authentication? && JrcContactCenter::ModulePolicy.new(context, :contact_center).view?
      raise Pundit::NotAuthorizedError unless allowed

      record.with_lock { scoped_payload(record, forms) }
    end
  end

  private

  def scoped_payload(record, forms)
    row = forms.state
    JrcContactCenter::QualificationFormVisibility.authorize!(row, account: @account, member: @member) if row
    record.account_user_id == @member.id ? own_payload(record) : legacy_payload(record)
  end

  def own_payload(record)
    context = { account: @account, account_user: @member, user: @member.user }
    forms = JrcContactCenter::QualificationForms.new(record)
    unless JrcContactCenter::ModulePolicy.new(context, :contact_center).operate?
      return legacy_payload(record).merge('acw_form_context_unavailable' => true) if forms.state

      return legacy_payload(record)
    end
    private_forms = forms.private_payload
    revision = JrcContactCenter::QualificationDraftRevision.token(record)
    record.operational_payload.merge('draft_revision' => revision).merge(private_forms)
  end

  def legacy_payload(record)
    record.operational_payload.merge('draft_revision' => JrcContactCenter::QualificationDraftRevision.token(record, include_forms: false))
  end
end

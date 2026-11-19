# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::AcwPoliciesController < Api::V1::Accounts::JrcContactCenter::BaseController
  def show
    authorize_contact_center!
    render_policy(JrcContactCenter::AcwPolicy.new(account: Current.account))
  end

  def update
    JrcContactCenter::AuthorityTransaction.call(account: Current.account, member: Current.account_user) do
      Current.user.reload
      raise Pundit::NotAuthorizedError unless Current.user.active_for_authentication?

      authorize_contact_center!(:configure?)
      authorize_global_configuration!
      policy = JrcContactCenter::AcwPolicy.new(account: Current.account)
      mode = params.key?(:voice_required) ? params[:voice_required] : :unchanged
      policy.update!(params.require(:limits).permit(:voice, :whatsapp),
                     voice_required: mode, **scoped_rules_options, **form_binding_options, **configuration_revision_options)
      render_policy(policy)
    end
  end

  private

  def render_policy(policy)
    response.headers['Cache-Control'] = 'no-store'
    item = policy.call.merge(id: Current.account.id.to_s, revision: policy.revision)
    if scoped_configuration_allowed?
      item[:voice_rules] = JrcContactCenter::AcwScopedRules.new(account: Current.account).call
      item[:voice_form_bindings] = JrcContactCenter::AcwFormBindingPolicy.new(account: Current.account).call
    end
    render json: base_payload.merge(item: item)
  end

  def scoped_rules_options
    return {} unless params.key?(:voice_rules)

    input = params[:voice_rules]
    return { voice_rules: input } unless input.is_a?(Array)

    { voice_rules: input.map { |row| row.respond_to?(:to_unsafe_h) ? row.to_unsafe_h : row } }
  end

  def form_binding_options
    return {} unless params.key?(:voice_form_bindings)

    input = params[:voice_form_bindings]
    return { voice_form_bindings: input } unless input.is_a?(Array)

    { voice_form_bindings: input.map { |row| row.respond_to?(:to_unsafe_h) ? row.to_unsafe_h : row } }
  end

  def scoped_configuration_allowed?
    coverage = JrcCrm::CorporateCoverage.new(account: Current.account, user: Current.user)
    contact_center_access.policy.configure? && (!coverage.configured? || coverage.group?)
  end

  def authorize_global_configuration!
    coverage = JrcCrm::CorporateCoverage.new(account: Current.account, user: Current.user)
    raise Pundit::NotAuthorizedError if coverage.configured? && !coverage.group?
  end
end

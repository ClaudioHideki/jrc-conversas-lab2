# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::KnowledgeController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  def index
    authorize :service_desk, :show?, policy_class: ::JrcServiceDesk::ModulePolicy
    # ArticlePolicy remains authoritative; this endpoint provides a read-only
    # projection of published articles, without another knowledge store.
    result = ::JrcServiceDesk::KnowledgeQuery.new(user_context: pundit_user).call(parameters: query_values)
    skip_policy_scope
    render json: base_payload.merge(result)
  end
end

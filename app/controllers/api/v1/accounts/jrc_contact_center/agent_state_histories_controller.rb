# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::AgentStateHistoriesController < Api::V1::Accounts::JrcContactCenter::BaseController
  before_action -> { response.headers['Cache-Control'] = 'no-store' }

  def index
    JrcContactCenter::AuthorityTransaction.call(account: Current.account, member: Current.account_user) do
      Current.user.reload
      raise Pundit::NotAuthorizedError unless Current.user.active_for_authentication?

      @contact_center_access = JrcContactCenter::AccessScope.new(user_context: pundit_user)
      authorize_contact_center!(:control?)
      render json: history_payload
    end
  end

  private

  def history_payload
    query = JrcContactCenter::AgentStateHistoryQuery.new(access: contact_center_access, params: params)
    params[:page] = '1' if params[:page].blank? # Always bound this new list; preserve legacy list callers.
    observed_at = Time.current
    presenter = JrcContactCenter::AgentStateHistoryPresenter.new(observed_at: observed_at)
    list_payload(query.call) { |event| presenter.call(event) }.merge(window: query.window, observed_at: observed_at.iso8601)
  end
end

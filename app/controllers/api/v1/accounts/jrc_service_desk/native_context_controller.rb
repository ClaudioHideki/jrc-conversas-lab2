# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::NativeContextController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  def customer
    raise ArgumentError unless query_values.empty?
    authorize strict_ticket, :view_customer?
    render json: ::JrcServiceDesk::CustomerContextService.new(user_context: pundit_user, ticket: strict_ticket).call
  end

  def conversation_navigation
    raise ArgumentError unless query_values.empty?
    authorize strict_ticket, :view_conversations?
    render json: ::JrcServiceDesk::ConversationNavigationService.new(user_context: pundit_user, ticket: strict_ticket).call(link_id: params[:record_id])
  end
end

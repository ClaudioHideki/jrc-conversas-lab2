class Api::V1::Accounts::Inboxes::AssignmentDiagnosticsController < Api::V1::Accounts::BaseController
  before_action -> { check_authorization(AssignmentPolicy) }

  def show
    inbox = Current.account.inboxes.find(params[:inbox_id])
    conversation = inbox.conversations.find(params[:conversation_id]) if params[:conversation_id].present?
    render json: AutoAssignment::Diagnostics.new(inbox: inbox, conversation: conversation).perform
  end
end

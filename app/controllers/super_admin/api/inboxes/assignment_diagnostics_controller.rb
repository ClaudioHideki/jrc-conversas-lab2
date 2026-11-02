class SuperAdmin::Api::Inboxes::AssignmentDiagnosticsController < SuperAdmin::Api::BaseController
  before_action :ensure_inbox!

  def show
    conversation = @inbox.conversations.find(params[:conversation_id]) if params[:conversation_id].present?
    render json: AutoAssignment::Diagnostics.new(inbox: @inbox, conversation: conversation).perform
  end
end

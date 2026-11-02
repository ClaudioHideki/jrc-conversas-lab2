class Api::V1::Widget::MessagesController < Api::V1::Widget::BaseController
  before_action :set_conversation, only: [:create]
  before_action :set_message, only: [:update]
  prepend_before_action :attachment_no_cache, only: [:attachment]

  def index
    @messages = conversation.nil? ? [] : message_finder.perform
  end

  def create
    @message = conversation.messages.new(message_params)
    build_attachment
    @message.save!
  end

  def attachment
    raise ActiveRecord::RecordNotFound unless auth_token_params[:inbox_id].to_s == @web_widget.inbox.id.to_s

    message = Message.where(account_id: @current_account.id, conversation_id: conversations.select(:id))
                     .where.not('private = ? OR message_type = ?', true, Message.message_types[:activity]).find(params[:message_id])
    file = message.attachments.where(account_id: @current_account.id).find(params[:attachment_id]).file
    raise ActiveRecord::RecordNotFound unless file.attached?

    access = JrcServiceDesk::ProtectedBlobAccess.new(blob: file.blob, user: nil,
                                                    widget_contact_inbox: @contact_inbox, widget_conversations: conversations)
    raise ActiveRecord::RecordNotFound unless access.protected?
    return render json: { code: 'attachment_scan_unavailable' }, status: :conflict unless file.blob.metadata['service_desk_scan_state'] == 'clean'
    raise ActiveRecord::RecordNotFound unless access.allowed?

    response.headers['Content-Type'] = file.blob.content_type_for_serving
    response.headers['Content-Disposition'] = ActionDispatch::Http::ContentDisposition.format(disposition: 'attachment', filename: file.filename.to_s)
    response.headers['Content-Length'] = file.byte_size.to_s
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['Content-Security-Policy'] = "sandbox; default-src 'none'"
    self.response_body = Enumerator.new { |stream| file.blob.download { |chunk| stream << chunk } }
  end

  def update
    if @message.content_type == 'input_email'
      @message.update!(submitted_email: contact_email)
      ContactIdentifyAction.new(
        contact: @contact,
        params: { email: contact_email, name: contact_name },
        retain_original_contact_name: true
      ).perform
    else
      @message.update!(message_update_params[:message])
    end
  rescue StandardError => e
    render json: { error: @contact.errors, message: e.message }.to_json, status: :internal_server_error
  end

  private

  def attachment_no_cache
    response.headers['Cache-Control'] = 'no-store'
  end

  def build_attachment
    return if params[:message][:attachments].blank?

    params[:message][:attachments].each do |uploaded_attachment|
      if uploaded_attachment.is_a?(String)
        blob = ActiveStorage::Blob.find_signed!(uploaded_attachment)
        access = JrcServiceDesk::ProtectedBlobAccess.new(blob: blob, user: nil,
                                                        widget_contact_inbox: @contact_inbox, widget_conversations: conversations)
        if access.protected? && !access.allowed?
          @message.errors.add(:attachments, 'Service Desk attachment access denied or security scan unavailable')
          raise ActiveRecord::RecordInvalid, @message
        end
      end
      attachment = @message.attachments.new(
        account_id: @message.account_id,
        file: uploaded_attachment
      )

      attachment.file_type = helpers.file_type(uploaded_attachment&.content_type) if uploaded_attachment.is_a?(ActionDispatch::Http::UploadedFile)
    end
  end

  def set_conversation
    return unless conversation.nil?

    @conversation = create_conversation
    apply_labels if permitted_params[:labels].present?
  end

  def apply_labels
    valid_labels = inbox.account.labels.where(title: permitted_params[:labels]).pluck(:title)
    @conversation.update_labels(valid_labels) if valid_labels.present?
  end

  def message_finder_params
    {
      filter_internal_messages: true,
      before: permitted_params[:before],
      after: permitted_params[:after]
    }
  end

  def message_finder
    @message_finder ||= MessageFinder.new(conversation, message_finder_params)
  end

  def message_update_params
    params.permit(message: [{ submitted_values: [:name, :title, :value, { csat_survey_response: [:feedback_message, :rating] }] }])
  end

  def permitted_params
    # timestamp parameter is used in create conversation method
    # custom_attributes and labels are applied when a new conversation is created alongside the first message
    params.permit(
      :id, :before, :after, :website_token,
      contact: [:name, :email],
      message: [:content, :referer_url, :timestamp, :echo_id, :reply_to],
      custom_attributes: {},
      labels: []
    )
  end

  def set_message
    # `conversation.messages.find` would be simpler, but `conversation` is `conversations.last`,
    # which means a visitor with more than one open thread could not edit a message in any
    # but their most recent one. Scoping across all of the visitor's conversations keeps the
    # happy path correct for that future multi-conversation widget flow.
    @message = Message.where(conversation_id: conversations.select(:id)).find(permitted_params[:id])
  end
end

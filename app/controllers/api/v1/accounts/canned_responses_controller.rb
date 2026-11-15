class Api::V1::Accounts::CannedResponsesController < Api::V1::Accounts::BaseController
  before_action :fetch_canned_response, only: [:update, :destroy, :preview, :file, :deliver]
  before_action :authorized_conversation, only: [:preview, :deliver]
  rescue_from CannedResponses::Delivery::Invalid, CannedResponses::Preview::Invalid do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def index
    render json: canned_responses.map { |record| payload(record) }
  end

  def create
    @canned_response = Current.account.canned_responses.new(canned_response_params)
    @canned_response.save!
    render json: payload(@canned_response)
  end

  def update
    @canned_response.update!(canned_response_params)
    render json: payload(@canned_response)
  end

  def preview
    authorize_file!
    response.headers['Cache-Control'] = 'no-store'
    resolved = CannedResponses::Preview.new(response: @canned_response, conversation: @conversation, user: Current.user).call
    render json: payload(@canned_response).merge(resolved).merge(revision: @canned_response.updated_at.iso8601(6), actor_id: Current.user.id)
  end

  def file
    blob = @canned_response.with_lock do
      raise ActiveRecord::RecordNotFound unless @canned_response.file.attached?

      if params.key?(:revision) || params.key?(:attachment_id)
        unless params[:revision] == @canned_response.updated_at.iso8601(6) && params[:attachment_id].to_s == @canned_response.file.id.to_s
          raise CannedResponses::Preview::Invalid, 'RESPONSE_CHANGED'
        end
      end
      authorize_file!
      @canned_response.file.blob
    end

    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    send_data blob.download, filename: blob.filename.to_s, type: blob.content_type, disposition: 'attachment'
  end

  def deliver
    message = CannedResponses::Delivery.new(response: @canned_response, conversation: @conversation, user: Current.user).call(
      content: params[:content], key: params[:delivery_key], confirmed: params[:confirmed], revision: params[:revision], expected_actor_id: params[:actor_id]
    )
    render json: message.push_event_data
  end

  def destroy
    @canned_response.destroy!
    head :ok
  end

  private

  def fetch_canned_response
    @canned_response = Current.account.canned_responses.find(params[:id])
  end

  def canned_response_params
    values = params.require(:canned_response).permit(:short_code, :content, :file)
    if params.dig(:canned_response, :file).present? && !values[:file].is_a?(ActionDispatch::Http::UploadedFile)
      raise ActionController::BadRequest, 'File must be an uploaded file, not a blob reference'
    end
    values[:file] = nil if ActiveModel::Type::Boolean.new.cast(params.dig(:canned_response, :remove_file)) && values[:file].blank?
    values
  end

  def authorized_conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize @conversation, :show?
  end

  def payload(record)
    data = record.as_json
    data['file'] = record.file_metadata if record.file.attached?
    data
  end

  def authorize_file!
    return unless @canned_response.file.attached?

    JrcServiceDesk::OutboundAttachments.authorize_blob!(@canned_response.file.blob, user: Current.user, account_id: Current.account.id)
  end

  def canned_responses
    if params[:search]
      Current.account.canned_responses
             .where('short_code ILIKE :search OR content ILIKE :search', search: "%#{params[:search]}%")
             .order_by_search(params[:search])

    else
      Current.account.canned_responses
    end
  end
end

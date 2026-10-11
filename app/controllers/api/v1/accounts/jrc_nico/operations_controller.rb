class Api::V1::Accounts::JrcNico::OperationsController < Api::V1::Accounts::BaseController
  around_action :operation_errors
  before_action :operator_session
  rescue_from Pundit::NotAuthorizedError, with: :forbidden
  rescue_from ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, with: :invalid
  rescue_from JrcNico::OperatorSession::Busy, JrcNico::RunCapacity::Exceeded, with: :busy
  rescue_from JrcNico::RuntimeClient::Error, with: :unavailable

  def show
    delegations = JrcNico::Delegation.where(account: Current.account, user: Current.user).order(updated_at: :desc).limit(30)
                                    .select { |d| @operator.access.policy(d.conversation).show? }
    visible = @operator.access.conversations
    answered = Current.account.messages.where(conversation_id: visible.map(&:id), message_type: :outgoing, private: false)
                      .reorder(nil).group(:conversation_id).maximum(:id)
    suggestions = visible.select do |c|
      c.custom_attributes.dig('nico_assistance', 'status') == 'pending' && c.custom_attributes['nico_control'] != 'active' &&
        %w[open pending].include?(c.status) && c.custom_attributes.dig('nico_assistance', 'message_id').to_i > answered.fetch(c.id, 0)
    end.first(8).map { |c| { conversation_id: c.display_id, name: c.contact.name, recommendation: c.custom_attributes['nico_assistance'] } }
    render json: { messages: @operator.session.messages, capacity: JrcNico::RunCapacity.snapshot(Current.account),
                   workflow: JrcNico::WorkflowSummary.for(@operator.session),
                   can_manage_knowledge: @operator.access.membership.administrator?,
                   commands: @operator.session.commands.where('created_at >= ?', @operator.session.context['visible_since'] || Time.current)
                                      .order(id: :desc).limit(100).map(&:snapshot),
                   tools: JrcNico::ToolCatalog.new(@operator.access).available, delegations: delegations.map(&:snapshot), suggestions: suggestions }
  end

  def notices
    records = JrcNico::Notice.where(account: Current.account, user: Current.user).includes(:conversation, :commands)
                            .order(updated_at: :desc).limit(60).select { |notice| notice.visible_to?(@operator.access) }
    render json: { notices: records.map(&:snapshot), unread_count: records.count { |notice| notice.read_at.nil? } }
  end

  def read_notice
    notice = JrcNico::Notice.find_by!(id: params[:id], account: Current.account, user: Current.user)
    raise Pundit::NotAuthorizedError unless notice.visible_to?(@operator.access)

    notice.update!(read_at: Time.current)
    notices
  end

  def retry_notice
    notice = JrcNico::Notice.find_by!(id: params[:id], account: Current.account, user: Current.user)
    raise Pundit::NotAuthorizedError unless notice.visible_to?(@operator.access)

    notice.with_lock do
      raise ArgumentError unless notice.kind == 'action' && notice.status == 'failed'
      raise JrcNico::OperatorSession::Busy if notice.commands.where(status: %w[planning awaiting_confirmation browser_pending executing unknown]).exists?

      notice.update!(status: 'planning', body: 'Retomando as etapas pendentes deste pedido.', read_at: nil)
    end
    JrcNico::NoticePlanJob.perform_later(notice.id)
    show
  end

  def ask
    input = params.permit(:message, :request_id, :conversation_id, :route_name)
    @operator.ask(message: input.fetch(:message), request_id: input.fetch(:request_id), conversation_id: input[:conversation_id],
                  route_name: input[:route_name])
    show
  end

  def transcribe
    result = JrcNico::OperationalInference.transcribe(account: Current.account, user: Current.user, upload: params.require(:audio))
    render json: { text: result.fetch('text') }
  end

  def conversations
    render json: @operator.access.conversations.first(50).map { |c| { id: c.display_id, name: c.contact.name, status: c.status, inbox: c.inbox.name } }
  end

  def prepare
    input = params.permit(:message, :request_id, :tool, arguments: {})
    @operator.ask(message: input.fetch(:message), request_id: input.fetch(:request_id), prepared: input.slice(:tool, :arguments).to_h)
    show
  end

  def confirm
    @operator.execute(command)
    show
  end

  def cancel
    @operator.cancel(command)
    show
  end

  def claim
    render json: @operator.browser_claim(command).snapshot
  end

  def receipt
    @operator.browser_result(command, params[:status], params[:detail])
    show
  end

  def takeover
    conversation = @operator.access.conversation(params.require(:conversation_id))
    JrcNico::DelegationService.stop(conversation, reason: 'human_takeover', user: Current.user)
    show
  end

  private

  def operation_errors
    yield
  rescue Pundit::NotAuthorizedError
    forbidden
  rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
    invalid
  rescue JrcNico::OperatorSession::Busy, JrcNico::RunCapacity::Exceeded => error
    busy(error)
  rescue JrcNico::RuntimeClient::Error => error
    unavailable(error)
  end

  def operator_session
    @operator = JrcNico::OperatorSession.new(account: Current.account, user: Current.user)
  end

  def command
    @operator.session.commands.find(params[:id])
  end

  def forbidden
    render json: { error: 'operation_forbidden' }, status: :forbidden
  end

  def invalid
    render json: { error: 'invalid_operation' }, status: :unprocessable_entity
  end

  def busy(error)
    if error.is_a?(JrcNico::RunCapacity::Exceeded)
      render json: { error: error.code, message: error.user_message }, status: :too_many_requests
    else
      render json: { error: 'capacity_unavailable', message: 'O NICO está processando outra solicitação desta sessão. Aguarde.' }, status: :too_many_requests
    end
  end

  def unavailable(error)
    render json: { error: error.code, message: error.user_message }, status: :service_unavailable
  end
end

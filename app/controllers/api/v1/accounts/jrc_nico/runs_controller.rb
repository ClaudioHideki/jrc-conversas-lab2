class Api::V1::Accounts::JrcNico::RunsController < Api::V1::Accounts::BaseController
  before_action :ensure_enabled
  before_action :set_conversation, only: [:index, :create]
  before_action :set_run, only: [:show, :cancel]

  def index
    render json: scope.where(conversation: @conversation).order(id: :desc).limit(10).map(&:snapshot)
  end

  def create
    input = params.permit(:message, :request_id, :agent_key)
    input[:agent_key] ||= 'nico'
    unless JrcNico::AgentCatalog.for_account(Current.account).any? { |agent| agent[:key] == input[:agent_key] }
      render json: { error: 'agent_unavailable' }, status: :unprocessable_entity
      return
    end
    created = false
    status = :accepted
    Current.account.with_lock do
      @run = scope.find_by(request_id: input[:request_id])
      if @run
        status = :conflict unless @run.fingerprint == JrcNico::Run.fingerprint_for(@conversation.id, input[:message], input[:agent_key])
      else
        reservation = JrcNico::RunCapacity.reservation_for!(Current.account, conversation: @conversation)
        @run = scope.new(input.merge(account: Current.account, user: Current.user, conversation: @conversation, reserved_tokens: reservation))
        created = @run.save
        status = :unprocessable_entity unless created
      end
    end
    if status != :accepted
      render json: { error: status.to_s }, status: status
      return
    end
    JrcNico::AnalyzeJob.perform_later(@run.id) if created
    render json: @run.snapshot, status: :accepted
  rescue JrcNico::RunCapacity::Exceeded => error
    render json: { error: error.code, message: error.user_message }, status: :too_many_requests
  end

  def show
    render json: @run.snapshot
  end

  def cancel
    Current.account.with_lock do
      @run.with_lock do
        if @run.status == 'queued'
          @run.reserved_tokens = 0
          @run.accounting = @run.accounting.merge('basis' => 'not_executed', 'cancelled_at' => Time.current.iso8601(6))
        end
        @run.update!(status: 'cancelled', finished_at: Time.current) if %w[queued running].include?(@run.status)
      end
    end
    render json: @run.snapshot
  end

  private

  def ensure_enabled
    return if Current.user.is_a?(User) && Current.account.custom_attributes['nico_enabled'] == true

    render json: { error: 'nico_disabled' }, status: :forbidden
  end

  def scope
    JrcNico::Run.where(account: Current.account, user: Current.user)
  end

  def set_conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize_conversation(@conversation)
  end

  def set_run
    @run = scope.find(params[:id])
    authorize_conversation(@run.conversation)
  end

  def authorize_conversation(conversation)
    JrcNico::Access.new(account: Current.account, user: Current.user, conversation: conversation).authorize!
  rescue Pundit::NotAuthorizedError
    render json: { error: 'conversation_forbidden' }, status: :forbidden
  end
end

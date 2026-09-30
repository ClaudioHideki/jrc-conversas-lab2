class Api::V1::Accounts::JrcNico::AssistanceController < Api::V1::Accounts::BaseController
  rescue_from Pundit::NotAuthorizedError, with: :forbidden
  before_action :set_conversation

  def show
    render json: snapshot
  end

  def authorize
    run = lead_result = binding = nil
    Current.account.with_lock do
      @conversation.with_lock do
        recommendation = current_recommendation
        raise ActiveRecord::RecordNotFound unless recommendation['status'] == 'pending'

        agent_key = params[:agent_key].presence || recommendation.fetch('agent_key')
        raise ArgumentError unless JrcNico::AgentCatalog.for_account(Current.account).any? { |agent| agent[:key] == agent_key }

        reservation = JrcNico::RunCapacity.reservation_for!(Current.account, conversation: @conversation)
        lead_result = create_lead if ActiveModel::Type::Boolean.new.cast(params[:create_lead])
        binding = bind_erp(recommendation['cnpj']) if ActiveModel::Type::Boolean.new.cast(params[:bind_erp]) && recommendation['cnpj'].present?
        run = create_run(agent_key, recommendation, reservation)
        update_recommendation(recommendation.merge('status' => 'authorized', 'authorized_by_id' => Current.user.id,
                                                   'authorized_at' => Time.current.iso8601, 'run_id' => run.id))
      end
    end
    JrcNico::AnalyzeJob.perform_later(run.id)
    render json: snapshot.merge(run: run.snapshot, lead: lead_result&.slice(:id, :name, :status), binding: binding&.public_snapshot), status: :accepted
  rescue Pundit::NotAuthorizedError
    forbidden
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'recommendation_unavailable' }, status: :not_found
  rescue JrcNico::RunCapacity::Exceeded
    render json: { error: 'too_many_requests' }, status: :too_many_requests
  rescue ArgumentError, ActiveRecord::RecordInvalid, JrcNico::ErpClient::Error
    render json: { error: 'authorization_invalid' }, status: :unprocessable_entity
  end

  def dismiss
    recommendation = current_recommendation
    update_recommendation(recommendation.merge('status' => 'dismissed', 'dismissed_by_id' => Current.user.id,
                                               'dismissed_at' => Time.current.iso8601))
    render json: snapshot
  end

  private

  def set_conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    @access = JrcNico::Access.new(account: Current.account, user: Current.user, conversation: @conversation).authorize!
  end

  def current_recommendation
    @conversation.custom_attributes.to_h.fetch('nico_assistance', {})
  end

  def snapshot
    { recommendation: current_recommendation, agents: JrcNico::AgentCatalog.for_account(Current.account),
      lead: @access.leads.order(id: :desc).first&.slice(:id, :name, :status),
      inbox_id: @conversation.inbox_id, channel_type: @conversation.inbox.channel_type }
  end

  def create_lead
    raise Pundit::NotAuthorizedError unless @access.crm?

    result = JrcCrm::ConversationLeadService.new(account: Current.account, conversation: @conversation, actor: Current.user).call
    lead = @access.leads.find_by(id: result.fetch(:lead).id)
    raise Pundit::NotAuthorizedError unless lead

    lead
  end

  def bind_erp(cnpj)
    membership = Current.account.account_users.find_by(user_id: Current.user.id)
    raise Pundit::NotAuthorizedError unless membership&.administrator? && JrcNico::ErpContext.account_allowed?(Current.account)

    setting = JrcNico::ErpSetting.find_by!(account: Current.account)
    resolved = JrcNico::ErpClient.new.call('resolve', { account_id: Current.account.id, mode: setting.mode, cnpj: cnpj })
    binding = JrcNico::ErpBinding.find_or_initialize_by(account: Current.account, contact: @conversation.contact)
    binding.update!(cnpj: resolved.fetch('cnpj'), customer_name: resolved.fetch('name'),
                    bemtevi_customer_id: resolved.fetch('bemtevi_customer_id'), helpdesk_company_id: resolved.fetch('helpdesk_company_id'),
                    mode: setting.mode, enabled: true, version: SecureRandom.hex(12), verified_by: Current.user)
    binding
  end

  def create_run(agent_key, recommendation, reservation)
    message = "Analise a nova mensagem do cliente, classificada como #{recommendation['intent']}. " \
              'Resuma a situação, consulte somente as fontes autorizadas, identifique dados faltantes e prepare uma resposta para revisão humana.'
    JrcNico::Run.create!(account: Current.account, user: Current.user, conversation: @conversation, request_id: SecureRandom.uuid,
                         message: message, agent_key: agent_key, reserved_tokens: reservation)
  end

  def update_recommendation(value)
    @conversation.update!(custom_attributes: @conversation.custom_attributes.to_h.merge('nico_assistance' => value))
  end

  def forbidden
    render json: { error: 'assistance_forbidden' }, status: :forbidden
  end
end


module JrcCrm
  class PublicProposalsController < ApplicationController
    before_action :set_proposal

    def show
      record_view! unless ActiveModel::Type::Boolean.new.cast(params[:preview])
      render layout: false
    end

    def pdf
      pdf = JrcCrm::ProposalPdfService.new(@proposal).call
      @proposal.events.create!(
        account_id: @proposal.account_id,
        event_type: 'pdf_generated',
        description: 'PDF da proposta gerado para visualização do cliente'
      )
      disposition = ActiveModel::Type::Boolean.new.cast(params[:download]) ? 'attachment' : 'inline'
      send_data pdf,
                filename: "#{@proposal.proposal_number.parameterize}-#{@proposal.title.parameterize.presence || @proposal.id}.pdf",
                type: 'application/pdf',
                disposition: disposition
    end

    def accept
      name = params[:accepted_by_name].to_s.strip
      document = params[:accepted_by_document].to_s.strip
      if name.blank? || document.blank?
        @acceptance_error = 'Informe o nome completo e o CPF ou documento do signatário.'
        render :show, layout: false, status: :unprocessable_entity
        return
      end

      if @proposal.accepted?
        JrcCrm::AcceptedProposalLifecycleService.new(proposal: @proposal, actor: @proposal.owner).call
        redirect_to jrc_crm_public_proposal_path(account_id: @proposal.account_id, token: params[:token], accepted: 1)
        return
      end

      unless @proposal.customer_response_allowed?
        @acceptance_error = 'Esta proposta ainda não está disponível para aceite.'
        render :show, layout: false, status: :unprocessable_entity
        return
      end

      ActiveRecord::Base.transaction do
        @proposal.accept_by_customer!(
          name: name,
          document: document,
          remote_ip: request.remote_ip,
          user_agent: request.user_agent
        )
        @proposal.events.create!(
          account_id: @proposal.account_id,
          event_type: 'accepted',
          description: 'Proposta aceita pelo cliente com evidência digital'
        )
      end
      JrcCrm::AcceptedProposalLifecycleService.new(proposal: @proposal.reload, actor: @proposal.owner).call
      redirect_to jrc_crm_public_proposal_path(account_id: @proposal.account_id, token: params[:token], accepted: 1)
    end

    def reject
      if @proposal.rejected?
        redirect_to jrc_crm_public_proposal_path(account_id: @proposal.account_id, token: params[:token], rejected: 1)
        return
      end

      unless @proposal.customer_response_allowed?
        redirect_to jrc_crm_public_proposal_path(
          account_id: @proposal.account_id,
          token: params[:token],
          response_error: 1
        )
        return
      end

      reason = params[:reason].to_s.strip
      @proposal.update!(status: 'rejected', rejected_at: Time.current)
      @proposal.events.create!(
        account_id: @proposal.account_id,
        event_type: 'rejected',
        description: "Proposta recusada ou com alteração solicitada: #{reason.presence || 'Sem motivo informado'}"
      )
      redirect_to jrc_crm_public_proposal_path(account_id: @proposal.account_id, token: params[:token], rejected: 1)
    end

    private

    def set_proposal
      @proposal = JrcCrm::Proposal.includes(:account, :owner, :deal, proposal_items: :product).find_by_raw_token(params[:token])
      raise ActiveRecord::RecordNotFound if @proposal.blank? || @proposal.account_id != params[:account_id].to_i || !@proposal.account.feature_enabled?('jrc_crm')
    end

    def record_view!
      first_view = @proposal.viewed_count.to_i.zero?
      @proposal.record_customer_view!
      @proposal.events.create!(
        account_id: @proposal.account_id,
        event_type: first_view ? 'viewed' : 'viewed_again',
        description: first_view ? 'Proposta visualizada pelo cliente' : 'Proposta visualizada novamente pelo cliente'
      )
    end
  end
end

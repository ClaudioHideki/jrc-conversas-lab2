module JrcCrm
  # Centralizes signer validation and proposal acceptance for every public entrypoint.
  # Acceptance evidence remains on the proposal (name/document/IP/user-agent/date) and
  # the commercial lifecycle is triggered only after a successful acceptance commit.
  class ProposalAcceptanceService
    Result = Struct.new(:success?, :proposal, :lifecycle, :errors, keyword_init: true)

    def initialize(proposal:, name:, document:, remote_ip:, user_agent:, actor: nil,
                   terms_accepted: false, require_terms: true, event_description: nil)
      @proposal = proposal
      @name = name.to_s.strip
      @document = JrcCustomers::TaxIdentifier.normalize(document)
      @remote_ip = remote_ip
      @user_agent = user_agent
      @actor = actor || proposal.owner
      @terms_accepted = ActiveModel::Type::Boolean.new.cast(terms_accepted)
      @require_terms = require_terms
      @event_description = event_description.presence || 'Proposta aceita pelo cliente com evidência digital'
    end

    def call
      return accepted_result if @proposal.accepted?

      errors = validation_errors
      return Result.new(success?: false, proposal: @proposal, lifecycle: nil, errors: errors) if errors.any?

      ActiveRecord::Base.transaction do
        @proposal.accept_by_customer!(
          name: @name,
          document: @document,
          remote_ip: @remote_ip,
          user_agent: @user_agent
        )
        @proposal.events.create!(
          account_id: @proposal.account_id,
          event_type: 'accepted',
          description: @event_description,
          metadata: {
            terms_accepted: @require_terms ? true : nil,
            acceptance_source: @require_terms ? 'public_link' : 'internal'
          }.compact
        )
      end

      accepted_result
    rescue ActiveRecord::RecordInvalid => e
      Result.new(
        success?: false,
        proposal: @proposal,
        lifecycle: nil,
        errors: e.record.errors.full_messages.presence || [e.message]
      )
    end

    private

    def accepted_result
      lifecycle = JrcCrm::AcceptedProposalLifecycleService.new(
        proposal: @proposal.reload,
        actor: @actor
      ).call
      Result.new(success?: true, proposal: @proposal.reload, lifecycle: lifecycle, errors: [])
    end

    def validation_errors
      errors = []
      errors << 'Informe o nome completo do signatário.' if @name.split.length < 2
      if @document.blank?
        errors << 'Informe o CPF ou CNPJ do signatário.'
      elsif !JrcCustomers::TaxIdentifier.valid?(@document)
        errors << 'CPF ou CNPJ inválido. Confira o documento informado.'
      end
      errors << 'Confirme que leu e aceita os termos desta proposta.' if @require_terms && !@terms_accepted
      errors << 'Esta proposta ainda não está disponível para aceite.' unless @proposal.customer_response_allowed?
      errors
    end
  end
end

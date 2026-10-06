module JrcCrm
  # Completes the commercial handoff after a proposal is accepted.
  # The service is intentionally idempotent: replaying an accepted proposal must
  # never create a second order, contract, project or customer record.
  class AcceptedProposalLifecycleService
    DEFAULT_IMPLEMENTATION_CHECKLIST = [
      'Kickoff',
      'Levantamento',
      'Configuração',
      'Integrações',
      'Treinamento',
      'Homologação',
      'Go-live'
    ].freeze

    def initialize(proposal:, actor: nil)
      @proposal = proposal
      @actor = actor || proposal.owner
      @account = proposal.account
      @warnings = []
    end

    def call
      return failure('A proposta precisa estar aceita antes de concluir o ciclo comercial.') unless @proposal.accepted?

      order = nil
      company = nil
      ActiveRecord::Base.transaction(requires_new: true) do
        synchronize_deal!
        order = JrcCrm::ProposalToOrderService.new(proposal: @proposal, actor: @actor).call
        apply_operational_defaults!(order)
        company = promote_company_to_customer!
        audit_acceptance_once!(order, company)
      end

      # Pending orders may already request a post-sale follow-up. Contract,
      # backoffice, commission and implementation remain gated by approval.
      JrcCrm::OrderWorkflowSyncService.new(order: order.reload, actor: @actor, event: 'proposal_accepted').call

      { success: true, order: order.reload, deal: @proposal.deal&.reload, company: company&.reload, warnings: @warnings }
    rescue StandardError => e
      Rails.logger.error("[JRC CRM] accepted proposal lifecycle failed for proposal=#{@proposal.id}: #{e.class}: #{e.message}")
      failure(e.message)
    end

    private

    def synchronize_deal!
      deal = @proposal.deal
      return unless deal
      return if deal.won?

      won_stage = deal.pipeline.stages.active.where(is_won: true).order(:position).first
      unless won_stage
        @warnings << 'O funil do negócio não possui uma etapa de ganho ativa; o pedido foi mantido, mas o negócio precisa ser revisado.'
        return
      end

      result = JrcCrm::DealPipelineService.new(deal: deal, stage: won_stage, actor: @actor).call
      unless result[:success]
        @warnings << "Não foi possível mover o negócio para ganho: #{result[:error]}"
        return
      end

      return if @account.jrc_crm_audit_events.for_resource('JrcCrm::Deal', deal.id).where(event_type: 'deal_won').exists?

      JrcCrm::AuditLoggerService.new(
        account: @account,
        event_type: 'deal_won',
        actor: @actor,
        resource: deal,
        from_value: 'open',
        to_value: 'won',
        metadata: { proposal_id: @proposal.id, source: 'proposal_accepted' }
      ).call
    end

    def apply_operational_defaults!(order)
      snapshot = (order.snapshot || {}).deep_stringify_keys
      items = @proposal.proposal_items.includes(:product).to_a
      products = items.filter_map(&:product)

      requires_contract = @proposal.monthly_cents.to_i.positive? || products.any? do |product|
        product.requires_contract? || Array(product.integrations).include?('contracts')
      end
      requires_implementation = @proposal.implementation_cents.to_i.positive? || products.any? do |product|
        Array(product.integrations).include?('implementation') || product.technical_requirements.present? || product.kind_project?
      end
      activation_days = products.map(&:activation_days).map(&:to_i).max.to_i
      activation_days = 30 if requires_implementation && activation_days <= 0

      defaults = {
        'sale_lifecycle_source' => 'accepted_proposal',
        'accepted_proposal_id' => @proposal.id,
        'generate_contract' => requires_contract,
        'send_to_implementation' => requires_implementation,
        'create_implementation_project' => requires_implementation,
        'activation_days' => activation_days
      }
      if requires_implementation
        defaults['activation_date'] = (Date.current + activation_days).iso8601
        defaults['checklist'] = DEFAULT_IMPLEMENTATION_CHECKLIST.map { |label| { 'label' => label, 'done' => false } }
      end
      if @proposal.follow_up_enabled? && @proposal.deal_id.present?
        defaults['create_follow_up'] = true
        defaults['follow_up_due_at'] = (@proposal.accepted_at || Time.current) + @proposal.follow_up_days.to_i.days
      end

      # Preserve explicit choices already made by a salesperson in an existing order.
      defaults.each { |key, value| snapshot[key] = value unless snapshot.key?(key) }
      snapshot['company_id'] ||= @proposal.customer_company&.id
      order.update!(snapshot: snapshot)
    end

    def promote_company_to_customer!
      return unless @account.feature_enabled?('jrc_customer_master')

      deal = @proposal.deal
      company = @proposal.customer_company
      return unless company
      return company unless %w[prospect lead].include?(company.relationship_type)

      JrcCustomers::CompanyWriter.new(account: @account, actor: @actor).save!(
        company: company,
        attributes: { relationship_type: 'customer' }
      )
    end

    def audit_acceptance_once!(order, company)
      return if @account.jrc_crm_audit_events.for_resource('JrcCrm::Proposal', @proposal.id).where(event_type: 'proposal_accepted').exists?

      JrcCrm::AuditLoggerService.new(
        account: @account,
        event_type: 'proposal_accepted',
        actor: @actor,
        resource: @proposal,
        from_value: 'sent/viewed',
        to_value: 'accepted',
        metadata: {
          deal_id: @proposal.deal_id,
          sales_order_id: order.id,
          company_id: company&.id,
          source: 'commercial_lifecycle'
        }
      ).call
    end

    def failure(message)
      { success: false, error: message, warnings: @warnings }
    end
  end
end

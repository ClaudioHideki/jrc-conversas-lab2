module Api
  module V1
    module Accounts
      module Crm
        class PublicProposalsController < ApplicationController
          before_action :find_valid_proposal

          def show
            render json: JrcCrm::ProposalSerializer.new(@proposal).as_json.merge(
              account: { name: @proposal.account.name },
              customer: serialize_customer,
              items: @proposal.proposal_items.map { |item| serialize_item(item) }
            )
          end

          def record_view
            first_view = @proposal.viewed_count.to_i.zero?
            @proposal.record_customer_view!
            @proposal.events.create!(
              account_id: @proposal.account_id,
              event_type: first_view ? 'viewed' : 'viewed_again',
              description: first_view ? 'Proposta visualizada pelo cliente' : 'Proposta visualizada novamente pelo cliente'
            )
            head :ok
          end

          def accept
            result = JrcCrm::ProposalAcceptanceService.new(
              proposal: @proposal,
              name: params[:accepted_by_name],
              document: params[:accepted_by_document],
              terms_accepted: params[:accepted_terms],
              remote_ip: request.remote_ip,
              user_agent: request.user_agent,
              actor: @proposal.owner,
              event_description: 'Proposta aceita pelo cliente via link público com evidência digital'
            ).call

            unless result.success?
              render json: { error: result.errors.join(' '), errors: result.errors }, status: :unprocessable_entity
              return
            end

            lifecycle = result.lifecycle || {}
            render json: {
              success: true,
              message: lifecycle[:success] == false ?
                'Proposta aceita. O Pedido não foi gerado automaticamente e precisa de revisão no CRM.' :
                'Proposta aceita com sucesso',
              proposal_status: result.proposal.status,
              accepted_at: result.proposal.accepted_at,
              sales_order: lifecycle[:order] && { id: lifecycle[:order].id, order_number: lifecycle[:order].order_number },
              lifecycle_warnings: lifecycle[:warnings],
              lifecycle_error: lifecycle[:success] == false ? lifecycle[:error] : nil
            }, status: :ok
          rescue ActiveRecord::StaleObjectError
            render json: { error: 'Conflito de versão na proposta', code: 'CONCURRENCY_CONFLICT' }, status: :conflict
          end

          def reject
            unless @proposal.customer_response_allowed?
              render json: { error: 'Esta proposta não está disponível para recusa.' }, status: :unprocessable_entity
              return
            end

            reason = params[:reason].to_s.strip
            @proposal.update!(rejected_at: Time.current, status: 'rejected')
            @proposal.events.create!(
              account_id: @proposal.account_id,
              event_type: 'rejected',
              description: "Proposta recusada pelo cliente: #{reason.presence || 'Sem motivo informado'}"
            )
            render json: { success: true, message: 'Proposta recusada' }, status: :ok
          end

          private

          def find_valid_proposal
            @proposal = JrcCrm::Proposal.find_by_raw_token(params[:token])
            if @proposal && (@proposal.account_id != params[:account_id].to_i || !@proposal.account.feature_enabled?('jrc_crm'))
              @proposal = nil
            end
            return if @proposal

            render json: {
              error: 'Proposta não encontrada, expirada ou revogada.',
              code: 'PROPOSAL_INVALID_OR_EXPIRED'
            }, status: :not_found
          end

          def serialize_customer
            contact = @proposal.deal.contact || @proposal.deal.contacts.first
            return nil unless contact

            { name: contact.name.presence || contact.identifier, email: contact.email }
          end

          def serialize_item(item)
            {
              name: item.name_snapshot,
              description: item.description_snapshot,
              quantity: item.quantity,
              unit_name: item.unit_name,
              billing_model: item.billing_model,
              unit_price_cents: item.unit_price_cents,
              setup_fee_cents: item.setup_fee_cents,
              discount_cents: item.discount_cents,
              total_cents: item.total_cents,
              recurring_total_cents: item.recurring_total_cents,
              initial_total_cents: item.initial_total_cents,
              included_quantity: item.included_quantity,
              included_unit: item.included_unit,
              overage_unit_price_cents: item.overage_unit_price_cents,
              activation_days: item.activation_days,
              validation_period_days: item.validation_period_days
            }
          end
        end
      end
    end
  end
end

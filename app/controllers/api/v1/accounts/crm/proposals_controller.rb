module Api
  module V1
    module Accounts
      module Crm
        class ProposalsController < BaseController
          before_action :set_proposal, only: [
            :show, :update, :destroy, :send_proposal, :pdf, :accept, :reject,
            :cancel, :duplicate, :request_approval, :approve, :convert_to_order
          ]
          before_action :ensure_unlocked_proposal!, only: [:update, :destroy, :request_approval, :approve, :accept, :reject, :cancel]

          around_action :lock_proposal_mutation, only: %i[update destroy request_approval approve accept reject cancel send_proposal duplicate]

          def index
            proposals = visible_to_current_user(crm_scope.jrc_crm_proposals)
            proposals = proposals.where(deal_id: params[:deal_id]) if params[:deal_id].present?
            proposals = proposals.where(status: params[:status]) if params[:status].present?
            proposals = proposals.where(owner_id: params[:owner_id]) if params[:owner_id].present?

            render json: proposals.includes(:owner, :deal, { events: :user }, proposal_items: :product)
                                  .order(updated_at: :desc)
                                  .map { |proposal| serialize(proposal) }
          end

          def show
            render json: serialize(@proposal)
          end

          def create
            deal = visible_to_current_user(crm_scope.jrc_crm_deals).find(params[:deal_id])
            proposal = JrcCrm::ProposalBuilderService.new(deal: deal, actor: Current.user).call
            render json: serialize(proposal), status: :created
          rescue StandardError => e
            render json: { errors: [e.message] }, status: :unprocessable_entity
          end

          def update
            attributes = proposal_params.to_h.symbolize_keys
            validate_proposal_owner!(attributes[:owner_id]) if attributes[:owner_id].present?
            normalize_payment_attributes!(attributes)
            if @proposal.proposal_items.exists?
              attributes.except!(:implementation_cents, :monthly_cents, :subtotal_cents, :total_cents)
            end

            if @proposal.update(attributes)
              commercial_changes = @proposal.saved_changes.keys - %w[updated_at]
              @proposal.reset_approvals! if commercial_changes.any?
              @proposal.recalculate_totals!
              audit_event!('updated', 'Proposta atualizada no CRM')
              render json: serialize(@proposal.reload)
            else
              render json: { errors: @proposal.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def destroy
            if @proposal.destroy
              head :no_content
            else
              render json: { errors: @proposal.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def duplicate
            duplicate = nil
            ActiveRecord::Base.transaction do
              duplicate = @proposal.dup
              duplicate.assign_attributes(
                proposal_number: nil,
                version_number: @proposal.version_number.to_i + 1,
                owner_id: Current.user.id,
                status: 'draft',
                approval_status: 'not_required',
                commercial_approval_status: 'not_required',
                financial_approval_status: 'not_required',
                technical_approval_status: 'not_required',
                public_token_digest: nil,
                public_token_expires_at: nil,
                public_token_revoked_at: nil,
                sent_at: nil,
                viewed_at: nil,
                last_viewed_at: nil,
                viewed_count: 0,
                accepted_at: nil,
                rejected_at: nil,
                canceled_at: nil,
                accepted_by_name: nil,
                accepted_by_document: nil,
                accepted_from_ip: nil,
                accepted_user_agent: nil,
                locked_at: nil,
                last_sent_channel: nil,
                last_sent_message_id: nil,
                last_sent_conversation_id: nil,
                title: "#{@proposal.title} - Versão #{@proposal.version_number.to_i + 1}"
              )
              duplicate.down_payment_cents = 0 # Items are copied before restoring the accepted entry.
              duplicate.save!

              @proposal.proposal_items.find_each do |item|
                attributes = item.attributes.except('id', 'proposal_id', 'created_at', 'updated_at')
                duplicate.proposal_items.create!(attributes)
              end
              duplicate.update!(down_payment_cents: @proposal.down_payment_cents)
              duplicate.recalculate_totals!

              duplicate.events.create!(
                account_id: crm_scope.id,
                event_type: 'duplicated',
                user_id: Current.user.id,
                description: "Nova versão criada a partir da proposta #{@proposal.proposal_number}"
              )
            end

            render json: serialize(duplicate.reload), status: :created
          rescue StandardError => e
            render json: { errors: [e.message] }, status: :unprocessable_entity
          end

          def request_approval
            unless @proposal.proposal_items.exists?
              render json: { errors: ['Adicione ao menos um produto ou serviço antes de solicitar aprovação.'] },
                     status: :unprocessable_entity
              return
            end

            @proposal.recalculate_totals!
            @proposal.update!(
              status: 'pending_approval',
              approval_status: 'pending',
              commercial_approval_status: 'pending',
              financial_approval_status: financial_approval_required? ? 'pending' : 'not_required',
              technical_approval_status: technical_approval_required? ? 'pending' : 'not_required'
            )
            audit_event!('approval_requested', 'Aprovação interna solicitada')
            render json: serialize(@proposal.reload)
          end

          def approve
            ensure_crm_admin!
            type = params[:approval_type].to_s
            column = {
              'commercial' => :commercial_approval_status,
              'financial' => :financial_approval_status,
              'technical' => :technical_approval_status
            }[type]
            raise ActionController::BadRequest, 'Tipo de aprovação inválido' unless column

            decision = params[:decision].to_s
            raise ActionController::BadRequest, 'Decisão de aprovação inválida' unless %w[approved rejected].include?(decision)

            @proposal.update!(column => decision)
            finalize_approval_state!
            audit_event!('approval_updated', "Aprovação #{type} atualizada")
            render json: serialize(@proposal.reload)
          end

          def pdf
            pdf_data = JrcCrm::ProposalPdfService.new(@proposal).call
            audit_event!('pdf_generated', 'PDF da proposta gerado no CRM')
            send_data pdf_data,
                      filename: "#{@proposal.proposal_number.parameterize}-#{@proposal.title.parameterize.presence || @proposal.id}.pdf",
                      type: 'application/pdf',
                      disposition: ActiveModel::Type::Boolean.new.cast(params[:download]) ? 'attachment' : 'inline'
          end

          def send_proposal
            if @proposal.accepted? || @proposal.rejected? || @proposal.canceled?
              render json: { errors: ['Esta proposta já está encerrada. Duplique-a para criar uma nova versão.'] },
                     status: :unprocessable_entity
              return
            end

            unless @proposal.proposal_items.exists?
              render json: { errors: ['Adicione ao menos um produto ou serviço antes de enviar a proposta.'] },
                     status: :unprocessable_entity
              return
            end

            @proposal.recalculate_totals!
            if @proposal.approval_status == 'pending'
              render json: { errors: ['A proposta ainda possui aprovações pendentes.'] }, status: :unprocessable_entity
              return
            end
            if @proposal.approval_status == 'rejected'
              render json: { errors: ['A proposta foi reprovada e não pode ser enviada.'] }, status: :unprocessable_entity
              return
            end
            if approval_required? && @proposal.approval_status != 'approved'
              render json: { errors: ['Os descontos ou requisitos técnicos exigem aprovação interna antes do envio.'] },
                     status: :unprocessable_entity
              return
            end

            result = JrcCrm::ProposalDeliveryService.new(
              proposal: @proposal,
              actor: Current.user,
              channel: params[:channel].presence || 'auto',
              base_url: request.base_url
            ).call

            render json: {
              message: 'Proposta enviada com sucesso',
              proposal: serialize(result[:proposal]),
              delivery: {
                conversation_id: result[:conversation].id,
                conversation_display_id: result[:conversation].display_id,
                inbox_id: result[:conversation].inbox_id,
                message_id: result[:message].id,
                channel: result[:proposal].last_sent_channel
              }
            }
          rescue StandardError => e
            render json: { errors: [e.message] }, status: :unprocessable_entity
          end

          def accept
            result = JrcCrm::ProposalAcceptanceService.new(
              proposal: @proposal,
              name: params[:accepted_by_name].presence || Current.user.name,
              document: params[:accepted_by_document],
              terms_accepted: true,
              require_terms: false,
              remote_ip: request.remote_ip,
              user_agent: request.user_agent,
              actor: Current.user,
              event_description: 'Proposta aceita internamente com evidência digital'
            ).call

            unless result.success?
              render json: { errors: result.errors }, status: :unprocessable_entity
              return
            end

            lifecycle = result.lifecycle || {}
            render json: {
              message: lifecycle[:success] == false ?
                'Proposta aceita. O Pedido não foi gerado automaticamente e precisa de revisão.' :
                'Proposta aceita',
              proposal: serialize(result.proposal),
              sales_order: lifecycle[:order] && {
                id: lifecycle[:order].id,
                order_number: lifecycle[:order].order_number,
                status: lifecycle[:order].status
              },
              lifecycle_warnings: lifecycle[:warnings],
              lifecycle_error: lifecycle[:success] == false ? lifecycle[:error] : nil
            }
          end

          def reject
            if @proposal.accepted?
              render json: { errors: ['Uma proposta aceita não pode ser rejeitada. Duplique-a para criar uma nova versão.'] },
                     status: :unprocessable_entity
              return
            end

            @proposal.update!(status: 'rejected', rejected_at: Time.current)
            audit_event!('rejected', 'Proposta rejeitada internamente')
            render json: { message: 'Proposta rejeitada', proposal: serialize(@proposal.reload) }
          end

          def cancel
            if @proposal.accepted?
              render json: { errors: ['Uma proposta aceita não pode ser cancelada. Duplique-a para criar uma nova versão.'] },
                     status: :unprocessable_entity
              return
            end

            @proposal.update!(status: 'canceled', canceled_at: Time.current)
            audit_event!('canceled', 'Proposta cancelada')
            render json: { message: 'Proposta cancelada', proposal: serialize(@proposal.reload) }
          end

          def convert_to_order
            order = JrcCrm::ProposalToOrderService.new(proposal: @proposal, actor: Current.user).call
            render json: { id: order.id, order_number: order.order_number, status: order.status, total_cents: order.total_cents }, status: :created
          rescue StandardError => e
            render json: { errors: [e.message] }, status: :unprocessable_entity
          end

          private

          def lock_proposal_mutation
            @proposal.with_lock do
              if !%w[duplicate send_proposal].include?(action_name) && @proposal.locked_for_editing?
                render json: { errors: ['A proposta aceita esta bloqueada. Crie uma nova versao.'] }, status: :unprocessable_entity
              else
                yield
              end
            end
          end

          def set_proposal
            @proposal = visible_to_current_user(crm_scope.jrc_crm_proposals).includes(
              :owner, :deal, { events: :user }, proposal_items: :product
            ).find(params[:id])
          end

          def ensure_unlocked_proposal!
            return unless @proposal.locked_for_editing?

            render json: { errors: ['A proposta aceita está bloqueada. Duplique-a para criar uma nova versão.'] },
                   status: :unprocessable_entity
          end

          def serialize(proposal)
            JrcCrm::ProposalSerializer.new(proposal, base_url: request.base_url).as_json
          end

          def audit_event!(event_type, description)
            @proposal.events.create!(
              account_id: crm_scope.id,
              event_type: event_type,
              user_id: Current.user&.id,
              description: description
            )
          end

          def approval_required?
            commercial_approval_required? || financial_approval_required? || technical_approval_required?
          end

          def commercial_approval_required?
            general_discount_percent > 10 || @proposal.proposal_items.any? do |item|
              threshold = item.product&.discount_approval_percent.to_f
              threshold.positive? && item_discount_percent(item) > threshold
            end
          end

          def financial_approval_required?
            return false if @proposal.subtotal_cents.to_i.zero?

            total_discount_percent = (@proposal.total_discount_cents.to_f / @proposal.subtotal_cents.to_i) * 100
            total_discount_percent > 10
          end

          def technical_approval_required?
            @proposal.proposal_items.any? do |item|
              item.product&.requires_contract? || item.product&.technical_requirements.present?
            end
          end

          def general_discount_percent
            return 0.0 if @proposal.subtotal_cents.to_i.zero?

            (@proposal.discount_cents.to_f / @proposal.subtotal_cents.to_i) * 100
          end

          def item_discount_percent(item)
            return 0.0 if item.gross_line_total_cents.zero?

            (item.applied_discount_cents.to_f / item.gross_line_total_cents) * 100
          end

          def finalize_approval_state!
            statuses = [
              @proposal.commercial_approval_status,
              @proposal.financial_approval_status,
              @proposal.technical_approval_status
            ]
            if statuses.include?('rejected')
              @proposal.update!(approval_status: 'rejected')
            elsif statuses.all? { |status| %w[approved not_required].include?(status) }
              @proposal.update!(approval_status: 'approved', status: 'draft')
            else
              @proposal.update!(approval_status: 'pending', status: 'pending_approval')
            end
          end

          def validate_proposal_owner!(owner_id)
            user = crm_scope.users.find_by(id: owner_id)
            raise Pundit::NotAuthorizedError unless user
            raise Pundit::NotAuthorizedError unless crm_admin? || user.id == @proposal.owner_id
          end

          def normalize_payment_attributes!(attributes)
            condition = attributes[:payment_condition].presence || @proposal.payment_condition
            case condition
            when 'cash'
              attributes[:down_payment_cents] = 0
              attributes[:installments_count] = 1
            when 'installments'
              attributes[:down_payment_cents] = 0
            end
            attributes[:monthly_cents] = 0 if attributes.key?(:has_monthly_fee) && !ActiveModel::Type::Boolean.new.cast(attributes[:has_monthly_fee])
            attributes[:shipping_cents] = 0 if attributes[:shipping_mode].present? && attributes[:shipping_mode] != 'separate'
          end

          def proposal_params
            params.require(:proposal).permit(
              :title, :discount_cents,
              :public_token_expires_at, :solution_description, :implementation_cents,
              :monthly_cents, :valid_until, :term_months, :commercial_notes,
              :next_steps, :notes, :customer_notes, :issuer_company_name,
              :issuer_tax_id, :issuer_unit, :payment_method, :billing_day,
              :first_billing_days, :taxes_included, :annual_adjustment_index,
              :renewal_type, :cancellation_penalty_percent, :follow_up_enabled,
              :follow_up_days, :owner_id, :shipping_cents, :shipping_mode, :payment_condition,
              :down_payment_cents, :installments_count, :has_monthly_fee, :shipping_in_installments
            )
          end
        end
      end
    end
  end
end

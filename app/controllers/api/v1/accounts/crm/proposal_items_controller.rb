module Api
  module V1
    module Accounts
      module Crm
        class ProposalItemsController < BaseController
          before_action :set_proposal
          before_action :ensure_unlocked_proposal!
          before_action :set_item, only: [:update, :destroy]

          around_action :lock_proposal_items

          def create
            item = @proposal.proposal_items.new(item_params)
            hydrate_product_snapshot(item)

            if item.save
              @proposal.reset_approvals!
              render json: serialize_proposal, status: :created
            else
              render json: { errors: item.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def update
            @item.assign_attributes(item_params)
            hydrate_product_snapshot(@item) if @item.product_id_changed?

            if @item.save
              @proposal.reset_approvals!
              render json: serialize_proposal
            else
              render json: { errors: @item.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def destroy
            @item.destroy!
            @proposal.reset_approvals!
            render json: serialize_proposal
          end

          private

          def lock_proposal_items
            @proposal.with_lock do
              if @proposal.locked_for_editing?
                render json: { errors: ['A proposta aceita esta bloqueada. Crie uma nova versao.'] }, status: :unprocessable_entity
              else
                yield
              end
            end
          end

          def set_proposal
            @proposal = visible_to_current_user(crm_scope.jrc_crm_proposals).find(params[:proposal_id])
          end

          def ensure_unlocked_proposal!
            return unless @proposal.locked_for_editing?

            render json: { errors: ['A proposta aceita está bloqueada para edição. Duplique-a para criar uma nova versão.'] },
                   status: :unprocessable_entity
          end

          def set_item
            @item = @proposal.proposal_items.find(params[:id])
          end

          def item_params
            params.require(:item).permit(
              :product_id, :name_snapshot, :description_snapshot, :quantity,
              :unit_price_cents, :discount_cents, :notes, :billing_model,
              :unit_name, :setup_fee_cents, :included_quantity, :included_unit,
              :overage_unit_price_cents, :activation_days, :validation_period_days
            )
          end

          def hydrate_product_snapshot(item)
            return if item.product_id.blank?

            product = crm_scope.jrc_crm_products.active.find(item.product_id)
            item.product = product
            item.name_snapshot = product.name if item.name_snapshot.blank?
            item.description_snapshot = product.description if item.description_snapshot.blank?
            item.unit_price_cents = product.unit_price_cents if item.unit_price_cents.blank? || item.unit_price_cents.zero?
            item.billing_model = product.billing_model
            item.unit_name = product.sales_unit.presence || 'unidade'
            item.setup_fee_cents = product.setup_fee_cents
            item.included_quantity = product.included_quantity
            item.included_unit = product.included_unit
            item.overage_unit_price_cents = product.overage_unit_price_cents
            item.activation_days = product.activation_days
            item.validation_period_days = product.validation_period_days
          end

          def serialize_proposal
            JrcCrm::ProposalSerializer.new(@proposal.reload).as_json
          end
        end
      end
    end
  end
end

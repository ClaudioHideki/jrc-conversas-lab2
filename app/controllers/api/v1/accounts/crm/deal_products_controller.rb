module Api
  module V1
    module Accounts
      module Crm
        class DealProductsController < BaseController
          before_action :set_deal
          before_action :set_deal_product, only: [:update, :destroy]
          around_action :lock_commercial_edit, only: %i[create update destroy]

          def index
            render json: serialize_products
          end

          def create
            item = @deal.deal_products.new(item_params)
            hydrate_product(item)
            if item.save
              recalculate_deal_value!
              render json: serialize_products, status: :created
            else
              render json: { errors: item.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def update
            @item.assign_attributes(item_params)
            hydrate_product(@item) if @item.product_id_changed?
            if @item.save
              recalculate_deal_value!
              render json: serialize_products
            else
              render json: { errors: @item.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def destroy
            @item.destroy!
            recalculate_deal_value!
            render json: serialize_products
          end

          private

          def lock_commercial_edit
            @deal.with_lock do
              yield
              JrcApprovals::CommercialInvalidation.call(resource: @deal.reload, user: Current.user) if response.successful?
            end
          end

          def set_deal
            @deal = visible_to_current_user(crm_scope.jrc_crm_deals).find(params[:deal_id])
          end

          def set_deal_product
            @item = @deal.deal_products.find(params[:id])
          end

          def item_params
            params.require(:item).permit(:product_id, :description_snapshot, :quantity, :unit_price_cents, :discount_cents, :notes)
          end

          def hydrate_product(item)
            return if item.product_id.blank?
            product = crm_scope.jrc_crm_products.active.find(item.product_id)
            item.product = product
            item.description_snapshot = product.description if item.description_snapshot.blank?
            item.unit_price_cents = product.unit_price_cents if item.unit_price_cents.blank? || item.unit_price_cents.zero?
          end

          def recalculate_deal_value!
            @deal.update_column(:value_cents, @deal.deal_products.sum(:total_cents))
          end

          def serialize_products
            @deal.deal_products.includes(:product).order(:id).map do |item|
              {
                id: item.id,
                product_id: item.product_id,
                product: item.product && { id: item.product_id, name: item.product.name, sku: item.product.sku },
                description_snapshot: item.description_snapshot,
                quantity: item.quantity,
                unit_price_cents: item.unit_price_cents,
                discount_cents: item.discount_cents,
                total_cents: item.total_cents,
                notes: item.notes
              }
            end
          end
        end
      end
    end
  end
end

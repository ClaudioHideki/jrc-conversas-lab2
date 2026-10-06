module Api
  module V1
    module Accounts
      module Crm
        class ProductsController < BaseController
          before_action :set_product, only: [:show, :update, :destroy, :toggle_active]

          def index
            products = crm_scope.jrc_crm_products
            products = products.where(active: ActiveModel::Type::Boolean.new.cast(params[:active])) if params[:active].present?
            products = products.where(category: params[:category]) if params[:category].present?
            products = products.where(product_type: params[:product_type]) if params[:product_type].present?
            products = products.where(billing_model: params[:billing_model]) if params[:billing_model].present?

            if params[:search].present?
              query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:search].to_s.strip)}%"
              products = products.where('name ILIKE :query OR sku ILIKE :query OR description ILIKE :query', query: query)
            end

            render json: products.order(active: :desc, name: :asc).map { |product| serialize(product) }
          end

          def show
            render json: serialize(@product)
          end

          def create
            ensure_crm_admin!
            product = crm_scope.jrc_crm_products.new(product_params)

            if product.save
              render json: serialize(product), status: :created
            else
              render json: { errors: product.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def update
            ensure_crm_admin!
            if @product.update(product_params)
              render json: serialize(@product)
            else
              render json: { errors: @product.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def destroy
            ensure_crm_admin!
            if @product.destroy
              head :no_content
            else
              render json: { errors: @product.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def toggle_active
            ensure_crm_admin!
            if @product.update(active: !@product.active)
              render json: serialize(@product)
            else
              render json: { errors: @product.errors.full_messages }, status: :unprocessable_entity
            end
          end

          private

          def set_product
            @product = crm_scope.jrc_crm_products.find(params[:id])
          end

          def serialize(product)
            JrcCrm::ProductSerializer.new(product, include_commercial_sensitive: crm_admin?).as_json
          end

          def product_params
            params.require(:product).permit(
              :name, :sku, :product_type, :category, :subcategory, :description,
              :sales_unit, :billing_model, :unit_price_cents, :cost_cents,
              :setup_fee_cents, :minimum_price_cents, :tax_rate, :commission_rate,
              :included_quantity, :included_unit, :overage_unit_price_cents,
              :minimum_quantity, :allow_variable_quantity, :activation_days,
              :validation_period_days, :rollover_allowance, :contract_term_months,
              :maximum_discount_percent, :discount_approval_percent, :renewal_type,
              :adjustment_index, :adjustment_period_months, :cancellation_penalty_percent,
              :allow_standalone_sale, :requires_contract, :fiscal_service_code,
              :proposal_template_name, :contract_template_name, :sales_notes,
              :technical_requirements, :scope_included, :scope_excluded,
              :currency, :active, tags: [], available_for: [], integrations: [],
              document_rules: [:key, :source, :label, :required, :blocking]
            )
          end
        end
      end
    end
  end
end

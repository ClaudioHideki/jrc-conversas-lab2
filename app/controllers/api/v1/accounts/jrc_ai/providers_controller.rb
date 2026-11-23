module Api
  module V1
    module Accounts
      module JrcAi
        class ProvidersController < BaseController
          before_action :ensure_ai_administrator!
          before_action :set_provider, only: [:show, :update, :destroy, :validate_configuration, :make_default]

          def index
            render json: Current.account.jrc_ai_providers.preferred_first.map { |provider| serialize(provider) }
          end

          def show
            render json: serialize(@provider)
          end

          def create
            provider = Current.account.jrc_ai_providers.new(provider_params)
            provider.settings = { 'usage_policy' => 'provider' }.merge(provider.settings)
            provider.created_by = Current.user

            if provider.save
              render json: serialize(provider), status: :created
            else
              render json: { errors: provider.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def update
            attributes = provider_params.to_h
            if attributes['api_key'].blank? && attributes[:api_key].blank?
              attributes.delete('api_key')
              attributes.delete(:api_key)
            end

            if @provider.update(attributes)
              render json: serialize(@provider)
            else
              render json: { errors: @provider.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def destroy
            @provider.destroy!
            head :no_content
          end

          def validate_configuration
            error = validation_error(@provider)
            if error.present?
              @provider.update(status: 'error', last_error: error, last_validated_at: Time.current)
              render json: serialize(@provider).merge(message: error), status: :unprocessable_entity
              return
            end

            @provider.update!(status: 'configured', last_error: nil, last_validated_at: Time.current)
            render json: serialize(@provider).merge(
              message: 'Configuracao validada localmente. A autenticacao real sera confirmada na primeira chamada de IA.',
              live_test_performed: false
            )
          end

          def make_default
            @provider.update!(default_provider: true, active: true)
            render json: serialize(@provider)
          end

          private

          def set_provider
            @provider = Current.account.jrc_ai_providers.find(params[:id])
          end

          def provider_params
            attributes = params.require(:provider).permit(
              :provider_type, :name, :api_key, :base_url, :default_model,
              :fast_model, :advanced_model, :monthly_token_limit,
              :monthly_budget_cents, :active, :default_provider, settings: {}
            )
            if attributes.key?(:settings)
              settings = attributes[:settings].to_h.except('provider_observation')
              attributes[:settings] = (@provider&.settings || {}).merge(settings)
            end
            attributes
          end

          def validation_error(provider)
            return 'Informe uma API Key.' unless provider.api_key_configured?
            return 'Informe o modelo padrao.' if provider.default_model.blank?
            return 'Informe a URL base para este provedor.' if provider.base_url.blank? && provider.provider_type != 'openai'

            nil
          end

          def serialize(provider)
            {
              id: provider.id,
              provider_type: provider.provider_type,
              name: provider.name,
              base_url: provider.base_url,
              default_model: provider.default_model,
              fast_model: provider.fast_model,
              advanced_model: provider.advanced_model,
              monthly_token_limit: provider.monthly_token_limit,
              monthly_budget_cents: provider.monthly_budget_cents,
              active: provider.active,
              default_provider: provider.default_provider,
              status: provider.status,
              api_key_configured: provider.api_key_configured?,
              masked_api_key: provider.masked_api_key,
              openai_compatible: provider.openai_compatible?,
              last_validated_at: provider.last_validated_at,
              last_error: provider.last_error,
              settings: provider.settings.except('provider_observation'),
              provider_observation: provider.settings['provider_observation'],
              created_at: provider.created_at,
              updated_at: provider.updated_at
            }
          end
        end
      end
    end
  end
end

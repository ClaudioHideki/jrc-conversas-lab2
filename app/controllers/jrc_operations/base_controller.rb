module JrcOperations
  class BaseController < ::Api::V1::Accounts::BaseController
    before_action :require_human_membership!
    around_action :use_operations_timezone
    rescue_from ActiveRecord::RecordNotFound do
      render json: { error: { code: 'NOT_FOUND', message: 'Registro nao encontrado ou sem acesso.' } }, status: :not_found
    end
    rescue_from Pundit::NotAuthorizedError do
      render json: { error: { code: 'FORBIDDEN', message: 'Seu perfil nao permite esta acao.' } }, status: :forbidden
    end
    rescue_from ActiveRecord::RecordInvalid do |error|
      render json: { error: { code: 'VALIDATION', message: error.record.errors.full_messages.join('; ') } }, status: :unprocessable_entity
    end
    rescue_from ArgumentError, ActionController::ParameterMissing do |error|
      render json: { error: { code: 'INVALID_REQUEST', message: error.message } }, status: :unprocessable_entity
    end
    rescue_from ActiveRecord::StaleObjectError, ActiveRecord::RecordNotUnique do
      render json: { error: { code: 'CONFLICT', message: 'O registro mudou ou ja existe. Atualize a tela antes de repetir.' } }, status: :conflict
    end
    rescue_from ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey, ActiveRecord::DeleteRestrictionError do
      render json: {
        error: { code: 'IN_USE', message: 'Registro vinculado a outros dados. Desative-o em vez de excluir.' }
      }, status: :unprocessable_entity
    end

    private

    def require_human_membership!
      raise Pundit::NotAuthorizedError unless Current.account_user && Current.user && Current.account_user.user_id == Current.user.id
    end
    def require_module!(kind)
      return if JrcOperations::Access.enabled?(Current.account, kind)
      render json: { error: { code: 'MODULE_DISABLED', message: 'Ative o modulo nas configuracoes correspondentes.' } }, status: :forbidden
    end
    def use_operations_timezone(&block)
      zone = Time.find_zone(Current.account&.reporting_timezone) || Time.find_zone!('America/Sao_Paulo')
      Time.use_zone(zone, &block)
    rescue Pundit::NotAuthorizedError
      render json: { error: { code: 'FORBIDDEN', message: 'Seu perfil nao permite esta acao.' } }, status: :forbidden
    end
    def pagination(relation)
      page = [params.fetch(:page, 1).to_i, 1].max
      per_page = params.fetch(:per_page, 25).to_i.clamp(1, 100)
      [relation.offset((page - 1) * per_page).limit(per_page), { page: page, per_page: per_page, total: relation.count }]
    end
    def correlation_id
      request.request_id
    end
    def assert_lock!(record, value)
      raise ArgumentError, 'Informe a versao do registro (lock_version).' if value.nil?
      raise ActiveRecord::StaleObjectError.new(record, 'update') unless record.lock_version == Integer(value)
    end
  end
end

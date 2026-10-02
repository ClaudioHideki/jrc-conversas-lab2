module Api
  module V1
    module Accounts
      module Crm
        class BaseController < Api::V1::Accounts::BaseController
          before_action :ensure_crm_enabled
          before_action :ensure_crm_access
          around_action :use_account_timezone

          rescue_from ActiveRecord::StaleObjectError, with: :handle_stale_object_conflict
          rescue_from JrcCrm::CommercialFinancials::InvalidTerms do |exception|
            render json: { errors: [exception.message], code: 'INVALID_COMMERCIAL_TERMS' }, status: :unprocessable_entity
          end

          rescue_from JrcCustomers::LegacyCompanyMapper::Conflict, JrcCustomers::LeadContactLinker::Conflict do |exception|
            render json: { error: exception.message, errors: [exception.message], code: 'REVIEW_REQUIRED' }, status: :conflict
          end

          private

          def ensure_crm_enabled
            return if Current.account.feature_enabled?('jrc_crm')

            render json: { error: 'CRM module is not enabled for this account' }, status: :forbidden
          end

          def crm_admin?
            Current.account_user.administrator?
          end

          def ensure_crm_access
            raise Pundit::NotAuthorizedError unless Current.account_user.permissions.include?('jrc_crm')
          end

          def crm_scope
            Current.account
          end

          def visible_to_current_user(relation, owner_column: :owner_id)
            return relation if crm_admin?

            relation.where(owner_column => Current.user.id)
          end

          def ensure_crm_admin!
            raise Pundit::NotAuthorizedError unless crm_admin?
          end

          def use_account_timezone(&block)
            timezone = Time.find_zone(Current.account.reporting_timezone) || Time.zone
            Time.use_zone(timezone, &block)
          end

          def parse_crm_time(value)
            return if value.blank?
            return value if value.is_a?(Time) || value.is_a?(DateTime)

            string_value = value.to_s
            parsed_time = if string_value.match?(/(?:Z|[+-]\d{2}:?\d{2})\z/)
                            Time.iso8601(string_value).in_time_zone
                          else
                            Time.zone.parse(string_value)
                          end
            raise ActionController::BadRequest, 'Data/hora inválida' unless parsed_time

            parsed_time
          rescue ArgumentError, TypeError
            raise ActionController::BadRequest, 'Data/hora inválida'
          end

          def handle_stale_object_conflict(exception)
            render json: {
              error: 'Conflito de concorrência: o registro foi modificado por outro usuário ou processo.',
              code: 'CONCURRENCY_CONFLICT',
              message: exception.message
            }, status: :conflict # HTTP 409
          end
        end
      end
    end
  end
end

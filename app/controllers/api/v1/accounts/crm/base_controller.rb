module Api
  module V1
    module Accounts
      module Crm
        class BaseController < Api::V1::Accounts::BaseController
          before_action :ensure_crm_enabled
          before_action :ensure_crm_access
          before_action :authorize_submitted_corporate_units!
          around_action :use_account_timezone

          rescue_from ActiveRecord::StaleObjectError, with: :handle_stale_object_conflict
          rescue_from JrcApprovals::Error do |exception|
            render json: { error: exception.code, code: exception.code }, status: :conflict
          end
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
            legacy_visible = crm_admin? ? relation : relation.where(owner_column => Current.user.id)
            JrcCrm::OrganizationalVisibility.new(account: crm_scope, user: Current.user, relation: legacy_visible).call
          end

          def ensure_crm_admin!
            raise Pundit::NotAuthorizedError unless crm_admin?
          end

          def corporate_scope(relation)
            JrcCrm::CorporateCoverage.new(account: crm_scope, user: Current.user).restrict(relation)
          end

          def corporate_records(association)
            corporate_scope(crm_scope.public_send(association))
          end

          def corporate_product(id, unit:)
            JrcCrm::CorporateIssuer.product!(account: crm_scope, user: Current.user, id: id, unit: unit)
          end

          def crm_metrics(**)
            JrcCrm::MetricsCalculatorService.new(account: crm_scope, actor: Current.user, **)
          end

          def goal_progress(goal, user_id: crm_admin? ? nil : Current.user.id)
            JrcCrm::GoalProgressService.new(goal: goal, actor: Current.user, user_id: user_id)
          end

          def authorize_submitted_corporate_units!
            return unless %w[create update preview].include?(action_name)
            return if controller_name == 'organization_structure'

            corporate_parameter_nodes.each { |node| authorize_corporate_unit_node!(node) }
            authorize_queue_company!
          end

          def corporate_parameter_nodes
            keys = %w[proposal sales_order product deal lead goal commission_program operations_queue]
            nodes = [params, *keys.filter_map { |key| params[key] }]
            nodes + nodes.filter_map { |node| node[:metadata] if node.respond_to?(:permit) }
          end

          def authorize_corporate_unit_node!(node)
            return unless node.respond_to?(:permit) && node[:business_unit_id].present?

            unit = crm_scope.jrc_crm_business_units.find(node[:business_unit_id])
            JrcCrm::CorporateIssuer.authorize!(account: crm_scope, user: Current.user, unit: unit)
          end

          def authorize_queue_company!
            queue = params[:operations_queue]
            return if queue&.dig(:operating_company_id).blank?
            raise Pundit::NotAuthorizedError unless JrcCrm::CorporateCoverage.new(account: crm_scope, user: Current.user)
                                                                             .company_allowed?(queue[:operating_company_id])
          end

          def use_account_timezone(&)
            timezone = Time.find_zone(Current.account.reporting_timezone) || Time.zone
            Time.use_zone(timezone, &)
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

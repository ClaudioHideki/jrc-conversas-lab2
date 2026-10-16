module Api
  module V1
    module Accounts
      module Crm
        class OrganizationStructureController < BaseController
          include JrcCrm::CorporateStructureParameters

          before_action :ensure_crm_admin!, except: :index
          before_action :authorize_scope_administration!, only: %i[create_user_scope update_user_scope destroy_user_scope
                                                                   create_team_scope update_team_scope destroy_team_scope]

          rescue_from ActiveRecord::RecordInvalid, with: :render_invalid
          rescue_from ActiveRecord::RecordNotDestroyed, ActiveRecord::DeleteRestrictionError, with: :render_in_use
          rescue_from JrcCustomers::CompanyWriter::StaleRevision, with: :render_stale
          rescue_from ArgumentError do |exception|
            render json: { errors: [exception.message] }, status: :unprocessable_entity
          end

          def show
            ensure_crm_admin!
            render json: service.snapshot
          end

          def update_settings
            before = crm_scope.custom_attributes.fetch(JrcCrm::OrganizationalStructureService::SETTINGS_KEY, {})
            payload = service.update_settings!(settings_params)
            audit!('organizational_structure_updated', crm_scope, before, payload)
            render json: service.snapshot
          end

          def create_company
            company = crm_scope.master_companies.new
            attrs = corporate_company_attributes(company)
            company.transaction do
              ensure_initial_segment!(attrs)
              JrcCustomers::CompanyWriter.new(account: crm_scope, actor: Current.user).save!(company: company, attributes: attrs)
              audit!('organizational_company_created', company, {}, company.attributes.slice(*attrs.keys.map(&:to_s)))
            end
            render json: service.snapshot, status: :created
          end

          def update_company
            company = internal_companies.find(params[:company_id])
            authorize_corporate_company!(company.id)
            attrs = corporate_company_attributes(company)
            if company_deactivation_blocked?(company, attrs)
              render json: { errors: ['Remova ou desative unidades e abrangências ativas antes de desativar a empresa.'] },
                     status: :unprocessable_entity
              return
            end
            before = company.attributes.slice(*attrs.keys.map(&:to_s))
            JrcCustomers::CompanyWriter.new(account: crm_scope, actor: Current.user).save!(
              company: company, attributes: attrs, expected_revision: params[:revision]
            )
            audit!('organizational_company_updated', company, before, company.attributes.slice(*attrs.keys.map(&:to_s)))
            render json: service.snapshot
          end

          def create_business_unit
            unit = crm_scope.jrc_crm_business_units.new(normalized_business_unit_params)
            crm_scope.with_lock { unit.save! }
            audit!('organizational_business_unit_created', unit, {}, unit.attributes)
            render json: service.snapshot, status: :created
          end

          def update_business_unit
            unit = crm_scope.jrc_crm_business_units.find(params[:business_unit_id])
            authorize_corporate_company!(unit.company_id)
            attrs = normalized_business_unit_params
            if unit_deactivation_blocked?(unit, attrs)
              render json: { errors: ['Remova ou desative abrangências ativas antes de desativar a unidade.'] }, status: :unprocessable_entity
              return
            end
            before = unit.attributes
            crm_scope.with_lock { unit.update!(attrs) }
            audit!('organizational_business_unit_updated', unit, before, unit.attributes)
            render json: service.snapshot
          end

          def destroy_business_unit
            unit = crm_scope.jrc_crm_business_units.find(params[:business_unit_id])
            authorize_corporate_company!(unit.company_id)
            before = unit.attributes
            unit.destroy!
            audit!('organizational_business_unit_deleted', unit, before, {})
            render json: service.snapshot
          end

          def create_team_scope
            scope = crm_scope.jrc_crm_team_scopes.new(normalized_team_scope_params)
            scope.save!
            audit!('organizational_team_scope_created', scope, {}, scope.attributes)
            render json: service.snapshot, status: :created
          end

          def update_team_scope
            scope = crm_scope.jrc_crm_team_scopes.find(params[:scope_id])
            before = scope.attributes
            scope.update!(normalized_team_scope_params)
            audit!('organizational_team_scope_updated', scope, before, scope.attributes)
            render json: service.snapshot
          end

          def destroy_team_scope
            scope = crm_scope.jrc_crm_team_scopes.find(params[:scope_id])
            before = scope.attributes
            scope.destroy!
            audit!('organizational_team_scope_deleted', scope, before, {})
            render json: service.snapshot
          end

          def create_user_scope
            scope = crm_scope.jrc_crm_user_business_units.new(normalized_user_scope_params.merge(structure_managed: true, permissions: {}))
            scope.save!
            audit!('organizational_user_scope_created', scope, {}, scope.attributes)
            render json: service.snapshot, status: :created
          end

          def update_user_scope
            scope = crm_scope.jrc_crm_user_business_units.structure_managed.find(params[:scope_id])
            before = scope.attributes
            scope.update!(normalized_user_scope_params.merge(structure_managed: true))
            audit!('organizational_user_scope_updated', scope, before, scope.attributes)
            render json: service.snapshot
          end

          def destroy_user_scope
            scope = crm_scope.jrc_crm_user_business_units.structure_managed.find(params[:scope_id])
            before = scope.attributes
            scope.destroy!
            audit!('organizational_user_scope_deleted', scope, before, {})
            render json: service.snapshot
          end

          private

          def authorize_scope_administration!
            coverage = JrcCrm::CorporateCoverage.new(account: crm_scope, user: Current.user)
            raise Pundit::NotAuthorizedError if coverage.configured? && !coverage.group?
          end

          def service
            @service ||= JrcCrm::OrganizationalStructureService.new(account: crm_scope, actor: Current.user)
          end

          def internal_companies
            crm_scope.master_companies.where(relationship_type: 'internal')
          end

          def team_scope_params
            params.require(:team_scope).permit(:team_id, :scope, :company_id, :business_unit_id, :active).to_h.symbolize_keys
          end

          def normalized_team_scope_params
            normalize_scope_links(team_scope_params, require_team: true)
          end

          def user_scope_params
            params.require(:user_scope).permit(:user_id, :team_id, :scope, :company_id, :business_unit_id, :active).to_h.symbolize_keys
          end

          def normalized_user_scope_params
            attrs = normalize_scope_links(user_scope_params, require_team: false)
            crm_scope.users.find(attrs[:user_id])
            attrs
          end

          def normalize_scope_links(attributes, require_team:)
            attrs = attributes.dup
            attrs[:scope] = attrs[:scope].to_s.upcase
            attrs[:team_id] = crm_scope.teams.find(attrs[:team_id]).id if require_team || attrs[:team_id].present?
            case attrs[:scope]
            when 'GROUP'
              attrs[:company_id] = nil
              attrs[:business_unit_id] = nil
            when 'COMPANY'
              attrs[:company_id] = internal_companies.find(attrs[:company_id]).id
              attrs[:business_unit_id] = nil
            when 'BUSINESS_UNIT'
              unit = crm_scope.jrc_crm_business_units.find(attrs[:business_unit_id])
              raise ActiveRecord::RecordInvalid.new(unit) if unit.company_id.blank?

              attrs[:business_unit_id] = unit.id
              attrs[:company_id] = unit.company_id
            else
              raise ActionController::BadRequest, 'invalid organizational scope'
            end
            attrs
          end

          def audit!(event_type, resource, from_value, to_value)
            JrcCrm::AuditLoggerService.new(account: crm_scope, event_type: event_type, actor: Current.user,
                                           resource: resource, from_value: from_value, to_value: to_value,
                                           metadata: { source: 'crm_organization_structure' }, ip_address: request.remote_ip).call
          end

          def render_invalid(exception)
            render json: { errors: exception.record.errors.full_messages }, status: :unprocessable_entity
          end

          def render_in_use(exception)
            render json: { errors: [exception.message.presence || 'Registro em uso; desative em vez de excluir.'] }, status: :unprocessable_entity
          end

          def render_stale(exception)
            render json: { errors: [exception.message], code: 'CONCURRENCY_CONFLICT' }, status: :conflict
          end
        end
      end
    end
  end
end

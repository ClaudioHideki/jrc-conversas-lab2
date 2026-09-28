module Api
  module V1
    module Accounts
      module Crm
        class LeadsController < BaseController
          before_action :set_lead, only: [:show, :update, :convert, :lose]

          def index
            leads = visible_to_current_user(crm_scope.jrc_crm_leads)
            leads = leads.where(status: normalized_filter_status) if params[:status].present?
            leads = leads.where(owner_id: params[:owner_id]) if params[:owner_id].present?
            leads = leads.where(conversation_id: params[:conversation_id]) if params[:conversation_id].present?
            
            if params[:search].present?
              leads = leads.where('name ILIKE :q OR email ILIKE :q', q: "%#{params[:search]}%")
            end

            render json: leads.includes(:owner).order(updated_at: :desc).map { |lead| JrcCrm::LeadSerializer.new(lead).as_json }
          end

          def from_conversation
            conversation = crm_scope.conversations.find(params.require(:conversation_id))
            result = JrcCrm::ConversationLeadService.new(
              account: crm_scope,
              conversation: conversation,
              actor: Current.user
            ).call
            lead = visible_to_current_user(crm_scope.jrc_crm_leads).find(result[:lead].id)

            render json: {
              lead: JrcCrm::LeadSerializer.new(lead).as_json,
              created: result[:created]
            }, status: result[:created] ? :created : :ok
          end

          def show
            render json: JrcCrm::LeadSerializer.new(@lead).as_json
          end

          def for_contact
            contact_lead_response(create: false)
          end

          def from_contact
            contact_lead_response(create: true)
          end

          def create
            lead = crm_scope.jrc_crm_leads.new(lead_params)
            lead.owner ||= Current.user
            
            if lead.save
              render json: JrcCrm::LeadSerializer.new(lead).as_json, status: :created
            else
              render json: { errors: lead.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def update
            previous_status = @lead.public_status
            attributes = lead_params.to_h
            attributes['status'] = normalized_write_status(attributes['status']) if attributes['status'].present?
            if @lead.update(attributes)
              log_status_change(previous_status) if previous_status != @lead.public_status
              render json: JrcCrm::LeadSerializer.new(@lead).as_json
            else
              render json: { errors: @lead.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def convert
            result = JrcCrm::LeadConversionService.new(
              lead: @lead,
              account: crm_scope,
              actor: Current.user,
              params: conversion_params
            ).call

            if result[:success]
              render json: {
                message: result[:created] ? 'Lead convertido em negócio.' : 'Este lead já estava convertido.',
                created: result[:created], lead: JrcCrm::LeadSerializer.new(@lead.reload).as_json,
                deal: JrcCrm::DealSerializer.new(result[:deal]).as_json
              }
            else
              render json: { error: result[:error] }, status: :unprocessable_entity
            end
          end

          def lose
            previous_status = @lead.public_status
            if @lead.update(status: 'unqualified')
              log_status_change(previous_status)
              render json: JrcCrm::LeadSerializer.new(@lead).as_json
            else
              render json: { errors: @lead.errors.full_messages }, status: :unprocessable_entity
            end
          end

          private

          def contact_lead_response(create:)
            result = JrcCrm::ContactLeadService.new(
              account: crm_scope, actor: Current.user, contact_id: params.require(:contact_id)
            ).call(create: create)
            render json: {
              lead: result[:lead] && JrcCrm::LeadSerializer.new(result[:lead]).as_json,
              created: result[:created]
            }, status: result[:created] ? :created : :ok
          rescue JrcCrm::ContactLeadService::AmbiguousContact
            render json: { code: 'CONTACT_HAS_MULTIPLE_LEADS' }, status: :conflict
          end

          def set_lead
            @lead = visible_to_current_user(crm_scope.jrc_crm_leads).find(params[:id])
          end

          def lead_params
            allowed = [:name, :company_name, :email, :phone, :source, :status, :contact_id, :conversation_id, :team_id,
                       :temperature, :notes]
            allowed << :owner_id if crm_admin?
            params.require(:lead).permit(*allowed)
          end

          def conversion_params
            allowed = [:deal_title, :company_name, :product_id, :product_name, :value_cents, :pipeline_id,
                       :stage_id, :probability, :expected_close_at, :team_id, :notes]
            allowed << :owner_id if crm_admin?
            attributes = params.permit(*allowed)
            attributes[:expected_close_at] = parse_crm_time(attributes[:expected_close_at]) if attributes[:expected_close_at].present?
            attributes
          end

          def normalized_filter_status
            params[:status] == 'discarded' ? %w[unqualified lost] : params[:status]
          end

          def normalized_write_status(status)
            normalized = status == 'discarded' ? 'unqualified' : status
            raise ActionController::BadRequest, 'Status de lead inválido' unless %w[new in_contact qualified unqualified].include?(normalized)

            normalized
          end

          def log_status_change(previous_status)
            JrcCrm::AuditLoggerService.new(
              account: crm_scope, event_type: 'lead_updated', actor: Current.user, resource: @lead,
              from_value: previous_status, to_value: @lead.public_status, metadata: { field: 'status' }
            ).call
          end
        end
      end
    end
  end
end

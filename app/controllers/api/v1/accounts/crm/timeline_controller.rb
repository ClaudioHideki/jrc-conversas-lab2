module Api
  module V1
    module Accounts
      module Crm
        class TimelineController < BaseController
          def index
            if params[:deal_id].present? && params[:lead_id].blank?
              deal_timeline
            elsif params[:lead_id].present? && params[:deal_id].blank?
              lead_timeline
            else
              render json: { error: 'Informe um negócio ou um lead para consultar o histórico.' }, status: :unprocessable_entity
            end
          end

          def deal_timeline
            deal = visible_to_current_user(crm_scope.jrc_crm_deals).find(params[:deal_id])
            
            timeline = JrcCrm::TimelineAggregatorService.new(resource: deal).call
            
            render json: { timeline: timeline }
          end

          def lead_timeline
            lead = visible_to_current_user(crm_scope.jrc_crm_leads).find(params[:lead_id])
            
            timeline = JrcCrm::TimelineAggregatorService.new(resource: lead).call
            
            render json: { timeline: timeline }
          end
        end
      end
    end
  end
end

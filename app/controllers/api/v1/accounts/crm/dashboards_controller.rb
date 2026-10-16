module Api
  module V1
    module Accounts
      module Crm
        class DashboardsController < BaseController
          def show
            JrcCrm::DefaultPipelineService.new(crm_scope).perform unless crm_scope.jrc_crm_pipelines.exists?
            start_date = params[:start_date] ? Date.parse(params[:start_date]) : 30.days.ago.to_date
            end_date = params[:end_date] ? Date.parse(params[:end_date]) : Date.current

            metrics = crm_metrics(
              pipeline_id: params[:pipeline_id],
              owner_id: crm_admin? ? params[:owner_id] : Current.user.id,
              start_date: start_date,
              end_date: end_date
            ).call

            render json: metrics
          end
        end
      end
    end
  end
end

module Api
  module V1
    module Accounts
      module Crm
        class ManagementController < BaseController
          def index
            unless crm_admin?
              render json: { error: 'Unauthorized' }, status: :unauthorized
              return
            end

            start_date = params[:start_date] ? Date.parse(params[:start_date]) : 30.days.ago.to_date
            end_date = params[:end_date] ? Date.parse(params[:end_date]) : Date.current

            users_metrics = crm_scope.users.map do |user|
              metrics = crm_metrics(
                owner_id: user.id,
                start_date: start_date,
                end_date: end_date
              ).call

              {
                user: { id: user.id, name: user.name, email: user.email },
                metrics: metrics
              }
            end

            render json: users_metrics
          end
        end
      end
    end
  end
end

module Api
  module V1
    module Accounts
      module Crm
        class FollowUpsController < BaseController
          before_action :set_follow_up, only: [:show, :update, :destroy, :complete]

          def index
            follow_ups = visible_to_current_user(crm_scope.jrc_crm_follow_ups, owner_column: :user_id)
            follow_ups = follow_ups.where(user_id: params[:user_id]) if params[:user_id].present?
            follow_ups = follow_ups.where(deal_id: params[:deal_id]) if params[:deal_id].present?

            render json: follow_ups.page(params[:page]).per(20)
          end

          def show
            responsible = crm_scope.users.find_by(id: @follow_up.user_id)
            render json: @follow_up.as_json.merge(user: responsible&.as_json(only: %i[id name]))
          end

          def create
            follow_up = crm_scope.jrc_crm_follow_ups.new(follow_up_params)
            follow_up.user = Current.user unless crm_admin?
            
            if follow_up.save
              render json: follow_up, status: :created
            else
              render json: { errors: follow_up.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def update
            if @follow_up.update(follow_up_params)
              render json: @follow_up
            else
              render json: { errors: @follow_up.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def destroy
            if @follow_up.destroy
              head :no_content
            else
              render json: { errors: @follow_up.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def complete
            if @follow_up.update(completed_at: Time.current)
              render json: @follow_up
            else
              render json: { errors: @follow_up.errors.full_messages }, status: :unprocessable_entity
            end
          end

          private

          def set_follow_up
            @follow_up = visible_to_current_user(crm_scope.jrc_crm_follow_ups, owner_column: :user_id).find(params[:id])
          end

          def follow_up_params
            params.require(:follow_up).permit(:notes, :due_at, :user_id, :deal_id, :lead_id)
          end
        end
      end
    end
  end
end

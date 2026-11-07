module Api
  module V1
    module Accounts
      module Crm
        class ActivitiesController < BaseController
          before_action :set_activity, only: [:show, :update, :destroy, :complete]

          def index
            activities = visible_to_current_user(
              crm_scope.jrc_crm_activities,
              owner_column: :user_id
            )
            activities = customer_segment_scope(activities)

            activities = activities.where(user_id: params[:user_id]) if params[:user_id].present?
            activities = activities.where(deal_id: params[:deal_id]) if params[:deal_id].present?
            activities = activities.where(lead_id: params[:lead_id]) if params[:lead_id].present?

            activities = activities
                         .includes(:user, :deal, :lead, :contact, :company)
                         .order(due_at: :asc)

            serialized_activities = activities.map do |activity|
              JrcCrm::ActivitySerializer.new(activity).as_json
            end

            render json: serialized_activities
          end

          def show
            render json: JrcCrm::ActivitySerializer.new(@activity).as_json
          end

          def create
            activity = crm_scope.jrc_crm_activities.new(activity_params)
            activity.user ||= Current.user

            result = JrcCrm::ActivityDispatchService.new(
              activity: activity,
              actor: Current.user
            ).call

            if result[:success]
              render json: JrcCrm::ActivitySerializer.new(result[:activity]).as_json, status: :created
            else
              render json: { errors: result[:error] }, status: :unprocessable_entity
            end
          end

          def update
            @activity.with_lock do
              if params.key?(:expected_version) && params[:expected_version] != @activity.updated_at.utc.iso8601(6)
                raise ActiveRecord::StaleObjectError.new(@activity, 'update')
              end

              if @activity.update(activity_params)
                audit_activity_edit! if params.key?(:expected_version)
                render json: JrcCrm::ActivitySerializer.new(@activity).as_json
              else
                render json: { errors: @activity.errors.full_messages }, status: :unprocessable_entity
              end
            end
          end

          def destroy
            if @activity.destroy
              head :no_content
            else
              render json: { errors: @activity.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def complete
            if @activity.update(completed_at: Time.current, status: 'completed')
              render json: JrcCrm::ActivitySerializer.new(@activity).as_json
            else
              render json: { errors: @activity.errors.full_messages }, status: :unprocessable_entity
            end
          end

          private

          def audit_activity_edit!
            changes = @activity.saved_changes.except('updated_at')
            JrcCustomers::Audit.record!(account: crm_scope, actor: Current.user, resource: @activity, event_type: 'activity_updated',
                                        metadata: { source: 'native_activity_editor', changed_fields: changes.keys },
                                        from_value: changes.transform_values(&:first).slice('due_at', 'user_id', 'deal_id', 'lead_id'),
                                        to_value: changes.transform_values(&:last).slice('due_at', 'user_id', 'deal_id', 'lead_id'))
          end

          def set_activity
            @activity = visible_to_current_user(
              crm_scope.jrc_crm_activities,
              owner_column: :user_id
            ).find(params[:id])
          end

          def activity_params
            attributes = params.require(:activity).permit(
              :activity_type,
              :title,
              :description,
              :due_at,
              :user_id,
              :deal_id,
              :lead_id
            )

            attributes[:due_at] = parse_crm_time(attributes[:due_at]) if attributes[:due_at].present?

            if attributes.key?(:deal_id)
              deal_id = attributes.delete(:deal_id)
              attributes[:deal] = deal_id.present? ? visible_to_current_user(crm_scope.jrc_crm_deals).find(deal_id) : nil
            end

            if attributes.key?(:lead_id)
              lead_id = attributes.delete(:lead_id)
              attributes[:lead] = lead_id.present? ? visible_to_current_user(crm_scope.jrc_crm_leads).find(lead_id) : nil
            end

            attributes
          end
        end
      end
    end
  end
end

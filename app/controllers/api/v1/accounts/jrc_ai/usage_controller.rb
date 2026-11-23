module Api
  module V1
    module Accounts
      module JrcAi
        class UsageController < BaseController
          before_action :ensure_ai_administrator!

          def index
            confirmed = Current.account.jrc_ai_usage_events.where('metadata @> ?', { usage_estimated: false }.to_json)
            month = confirmed.current_month
            today = confirmed.today

            render json: {
              totals: totals(month).merge(tokens_today: today.sum(:total_tokens)),
              by_agent: grouped(month, :agent_key),
              by_model: grouped(month, :model),
              by_user: grouped_users(month),
              recent: month.order(created_at: :desc).limit(50).map { |event| serialize(event) }
            }
          end

          private

          def totals(scope)
            {
              input_tokens: scope.sum(:input_tokens),
              output_tokens: scope.sum(:output_tokens),
              total_tokens: scope.sum(:total_tokens),
              executions: scope.count
            }
          end

          def grouped(scope, column)
            scope.group(column).sum(:total_tokens).map { |key, value| { key: key.presence || 'nao_informado', tokens: value } }
          end

          def grouped_users(scope)
            names = Current.account.users.where(id: scope.where.not(user_id: nil).distinct.pluck(:user_id)).index_by(&:id)
            scope.group(:user_id).sum(:total_tokens).map do |user_id, value|
              { key: user_id, label: names[user_id]&.name || names[user_id]&.email || 'Sistema', tokens: value }
            end
          end

          def serialize(event)
            {
              id: event.id,
              agent_key: event.agent_key,
              feature: event.feature,
              model: event.model,
              input_tokens: event.input_tokens,
              output_tokens: event.output_tokens,
              total_tokens: event.total_tokens,
              user_id: event.user_id,
              provider_id: event.provider_id,
              created_at: event.created_at
            }
          end
        end
      end
    end
  end
end

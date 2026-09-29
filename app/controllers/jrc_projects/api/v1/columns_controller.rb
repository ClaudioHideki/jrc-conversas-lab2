module JrcProjects
  module Api
    module V1
      class ColumnsController < BaseController
        before_action :context
        def index
          render json: { data: @board.board_columns.order(:position, :id) }
        end
        def create
          authorize_capability!('projects.board.manage', project: @project)
          @project.with_lock do
            ensure_project_editable!(@project)
            raise ArgumentError, 'Limite de 12 colunas por quadro.' if @board.board_columns.count >= 12
            record = @board.board_columns.create!(column_params.merge(account: Current.account))
            render json: { data: record }, status: :created
          end
        end
        def update
          authorize_capability!('projects.board.manage', project: @project)
          @project.with_lock do
            ensure_project_editable!(@project)
            record = @board.board_columns.find(params[:id])
            target = column_params[:status_key]
            if target.present? && target != record.status_key && %w[backlog completed].include?(record.status_key) && @board.board_columns.where(status_key: record.status_key).count <= 1
              raise ArgumentError, 'Mantenha ao menos uma coluna A fazer e uma Concluido.'
            end
            record.update!(column_params)
            render json: { data: record }
          end
        end
        def destroy
          authorize_capability!('projects.board.manage', project: @project)
          @project.with_lock do
            ensure_project_editable!(@project)
            record = @board.board_columns.find(params[:id])
            raise ArgumentError, 'Mantenha ao menos uma coluna A fazer e uma Concluido.' if %w[backlog completed].include?(record.status_key) && @board.board_columns.where(status_key: record.status_key).count <= 1
            record.destroy!; head :no_content
          end
        end
        private
        def context
          @project = scoped_project
          @board = @project.boards.find(params[:board_id])
        end
        def column_params
          params.require(:board_column).permit(:name, :status_key, :position, :wip_limit)
        end
      end
    end
  end
end

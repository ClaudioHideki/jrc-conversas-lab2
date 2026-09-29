module JrcOperations
  class LinksController < BaseController
    def index
      render json: { data: Related.new(account_user: Current.account_user, source: source_params).call }
    end

    def create
      raise ArgumentError, 'Ative os modulos antes de vincular.' unless Access.ready?
      link = Linker.new(account_user: Current.account_user, correlation_id: correlation_id).create!(attributes: source_params)
      render json: { data: { id: link.id } }, status: :created
    end

    def destroy
      Linker.new(account_user: Current.account_user, correlation_id: correlation_id).destroy!(id: params[:id], source: source_params)
      head :no_content
    end

    private

    def source_params
      params.permit(:ticket_id, :project_id, :task_id, :conversation_display_id, :contact_id, :deal_id)
    end
  end
end

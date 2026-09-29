module Api::V1::Accounts::Crm
  class ContractTemplatesController < BaseController
    before_action :ensure_crm_admin!, except: %i[index show]
    before_action :set_template, only: %i[show update destroy]

    def index
      templates = crm_scope.jrc_crm_contract_templates.order(active: :desc, name: :asc)
      render json: templates
    end

    def show
      render json: @template
    end

    def create
      template = crm_scope.jrc_crm_contract_templates.create!(template_params)
      render json: template, status: :created
    end

    def update
      @template.update!(template_params)
      render json: @template.reload
    end

    def destroy
      @template.destroy!
      head :no_content
    end

    private

    def set_template
      @template = crm_scope.jrc_crm_contract_templates.find(params[:id])
    end

    def template_params
      params.require(:contract_template).permit(:name, :category, :description, :body, :active, variables: [])
    end
  end
end

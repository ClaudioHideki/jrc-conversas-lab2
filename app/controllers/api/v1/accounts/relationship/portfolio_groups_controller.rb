class Api::V1::Accounts::Relationship::PortfolioGroupsController < Api::V1::Accounts::Relationship::BaseController
  before_action { response.headers['Cache-Control'] = 'no-store' }

  def index
    render json: reader.index(page: params.fetch(:page, 1), query: params[:q], status: params.fetch(:status, 'active'))
  end

  def show
    render json: reader.show(params[:id])
  end

  def workload
    render json: JrcRelationship::PortfolioGroupWorkload.new(relationship_context).call(params[:id])
  end

  def history
    render json: JrcRelationship::PortfolioGroupHistory.new(relationship_context)
                                                       .index(params[:id], page: params.fetch(:page, 1),
                                                                           kind: params.fetch(:kind, ''), period: report_period)
  end

  def history_detail
    render json: JrcRelationship::PortfolioHistoryDetails.new(relationship_context)
                                                       .call(group_id: params[:id], event_id: params.require(:event_id))
  end

  def export_history
    render json: JrcRelationship::PortfolioGroupHistory.new(relationship_context)
                                                       .export(params[:id], kind: params.fetch(:kind, ''), period: report_period)
  end

  def create
    render json: writer.create!(attributes), status: :created
  end

  def update
    render json: writer.update!(params[:id], attributes: attributes,
                                             expected_version: params[:expected_version], reason: params[:reason])
  end

  def customers
    render json: reader.customers(params[:id], page: params.fetch(:page, 1))
  end

  def update_customers
    render json: writer.set_customers!(params[:id], ids: params[:assignment_ids], active: params[:active],
                                                    expected_version: params[:expected_version], reason: params[:reason])
  end

  def customer_review
    render json: JrcRelationship::PortfolioGroupCustomerReview.new(relationship_context).call(params[:id], ids: params[:assignment_ids])
  end

  private

  def attributes
    # Preserve invalid collection shapes for validation instead of silently
    # dropping an owner/scope field through scalar strong-parameter filtering.
    input = params.require(:portfolio_group)
    raise ActionController::BadRequest, 'Portfolio fields must be an object' unless input.is_a?(ActionController::Parameters)

    input.to_unsafe_h.slice(*JrcRelationship::PortfolioGroups::FIELDS)
  end

  def reader
    JrcRelationship::PortfolioGroupReader.new(relationship_context)
  end

  def writer
    JrcRelationship::PortfolioGroups.new(relationship_context)
  end
end

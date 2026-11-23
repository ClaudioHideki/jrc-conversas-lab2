# frozen_string_literal: true

class JrcCulture::ImportsController < JrcCulture::BaseController
  before_action :require_admin

  def index
    render json: { runs: imports.scope.order(id: :desc).limit(50).map { |run| run_data(run) } }
  end

  def show
    run = imports.scope.find(params[:id])
    render json: run_data(run).merge(rows: imports.preview(run))
  end

  def create
    run = imports.create!(unit_id: params.require(:unit_id), file: params.require(:file))
    render json: run_data(run).merge(rows: imports.preview(run)), status: :created
  end

  def apply
    selected = params.permit(selections: %i[line member_id])[:selections]
    render json: run_data(imports.apply!(id: params[:id], selections: selected))
  end

  def file
    run = imports.scope.find(params[:id])
    protected_file(run.blob)
  end

  private

  def require_admin
    access.admin!
  end

  def imports
    @imports ||= JrcCulture::Imports.new(access)
  end

  def run_data(run)
    { id: run.id, unit_id: run.unit_id, created_at: run.created_at, applied_at: run.applied_at, result: run.result }
  end
end

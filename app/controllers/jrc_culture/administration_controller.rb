# frozen_string_literal: true

class JrcCulture::AdministrationController < JrcCulture::BaseController
  before_action :require_admin

  def setup
    units = access.admin_units.includes(:operating_company).order(:name).map do |unit|
      { id: unit.id, name: unit.name, company_id: unit.company_id, company: unit.operating_company.name }
    end
    if access.admin_unit_ids.include?(nil)
      units << { id: JrcCulture::Access::ACCOUNT_SCOPE, name: JrcCulture::Access::ACCOUNT_SCOPE_LABEL,
                 company_id: nil, company: access.account.name }
    end
    scope_keys = units.pluck(:id)
    versions = access.admin_versions.includes(:assets, :audiences).order(id: :desc).limit(200)
    render json: {
      units: units,
      versions: versions.map do |version|
        ids = version.audiences.map { |audience| audience.unit_id || JrcCulture::Access::ACCOUNT_SCOPE }
        version_data(version).merge(state: version.state, unit_ids: ids & scope_keys, manageable: ids.difference(scope_keys).empty?)
      end
    }
  end

  def report
    render json: JrcCulture::Report.new(access, report_filters).page
  end

  def export
    rows = JrcCulture::Export.new(JrcCulture::Report.new(access, report_filters).export_rows)
    type = params[:type]
    case type
    when 'xlsx' then send_data rows.xlsx, filename: 'manual-de-cultura-relatorio.xlsx', type: JrcCulture::Files::TYPES.fetch(type)
    when 'pdf' then send_data rows.pdf, filename: 'manual-de-cultura-relatorio.pdf', type: 'application/pdf'
    else head :bad_request
    end
  end

  def create_version
    fields = params.permit(:manual_id, :title, :description, :pdf, :pptx, unit_ids: [])
    version = JrcCulture::Publications.new(access).create!(
      manual_id: fields[:manual_id], title: fields[:title], description: fields[:description].to_s,
      pdf: fields[:pdf], pptx: fields[:pptx], unit_ids: fields[:unit_ids]
    )
    render json: version_data(version), status: :created
  end

  def transition
    version = JrcCulture::Publications.new(access).transition!(params[:id], params.require(:transition))
    render json: version_data(version).merge(state: version.state)
  end

  def file
    version = access.admin_versions.find(params[:id])
    protected_file(version.assets.find_by!(kind: params[:kind]).blob)
  end

  private

  def report_filters
    params.permit(:company_id, :unit_id, :department, :culture_person_query, :version_id, :state, :from, :to, :page)
  end

  def require_admin
    access.admin!
  end
end

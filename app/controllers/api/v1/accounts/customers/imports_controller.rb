class Api::V1::Accounts::Customers::ImportsController < Api::V1::Accounts::Customers::BaseController
  before_action :authorize_admin!
  rescue_from JrcCustomers::CompanyImport::InvalidImport do |exception|
    render json: { error: exception.message }, status: :unprocessable_entity
  end

  def preview
    render json: importer.preview
  end

  def apply
    render json: importer.apply!(token: params.require(:token))
  end

  private

  def importer
    file = params.require(:file)
    raise ActionController::BadRequest, 'Upload a UTF-8 CSV file' unless file.respond_to?(:read) && file.respond_to?(:size)
    raise ActionController::BadRequest, 'File exceeds 1 MiB' if file.size > JrcCustomers::CompanyImport::MAX_BYTES

    JrcCustomers::CompanyImport.new(account: Current.account, actor: Current.user,
                                    content: file.read(JrcCustomers::CompanyImport::MAX_BYTES + 1))
  end
end

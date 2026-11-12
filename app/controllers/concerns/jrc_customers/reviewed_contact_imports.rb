# Keep the legacy importer intact for accounts without the master directory.
# Enabled accounts must review through the scoped, actor-bound central instead.
module JrcCustomers::ReviewedContactImports
  def import
    return super if params[:import_file].blank? || !Current.account.feature_enabled?('jrc_customer_master')

    render json: { error: 'Use a Central de Importações para revisar o arquivo antes da gravação.', code: 'REVIEW_REQUIRED',
                   review_path: "/app/accounts/#{Current.account.id}/customers/imports?kind=contacts" }, status: :conflict
  end
end

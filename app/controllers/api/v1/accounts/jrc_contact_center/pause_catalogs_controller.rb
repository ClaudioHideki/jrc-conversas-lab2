class Api::V1::Accounts::JrcContactCenter::PauseCatalogsController < Api::V1::Accounts::JrcContactCenter::BaseController
  rescue_from JrcContactCenter::PauseReasonDefinition::Invalid, with: :render_invalid_catalog

  def show
    authorize_catalog!
    render_catalog
  end

  def update
    JrcContactCenter::AuthorityTransaction.call(account: Current.account, member: Current.account_user) do
      Current.user.reload
      raise Pundit::NotAuthorizedError unless Current.user.active_for_authentication?

      authorize_catalog!
      catalog.update!(catalog_document, expected_revision: params[:expected_revision], activation_confirmed: params[:activation_confirmed])
      render_catalog
    end
  end

  private

  def authorize_catalog!
    authorize_contact_center!(:configure?)
    coverage = JrcContactCenter::CorporateCoverage.new(account: Current.account, user: Current.user)
    raise Pundit::NotAuthorizedError if coverage.configured? && !coverage.group?
  end

  def catalog
    JrcContactCenter::PauseCatalog.new(account: Current.account)
  end

  # This is a bounded typed configuration document, never model mass assignment.
  # Do not filter malformed entries/ID arrays into a broader empty scope.
  def catalog_document
    document = params.require(:pause_catalog)
    valid = document.is_a?(ActionController::Parameters) && document.keys.sort == %w[enforced entries]
    raise JrcContactCenter::PauseReasonDefinition::Invalid, ['entries'] unless valid

    entries = document[:entries]
    valid = entries.is_a?(Array) && entries.length <= JrcContactCenter::PauseCatalog::MAX_ENTRIES
    raise JrcContactCenter::PauseReasonDefinition::Invalid, ['entries'] unless valid

    { 'enforced' => document[:enforced], 'entries' => entries.map { |entry| entry_document(entry) } }
  end

  def entry_document(entry)
    fields = JrcContactCenter::PauseReasonDefinition::ALL_FIELDS
    valid = entry.is_a?(ActionController::Parameters) && (entry.keys - fields).empty?
    raise JrcContactCenter::PauseReasonDefinition::Invalid, ['entries'] unless valid

    fields.each_with_object({}) { |field, values| values[field] = entry[field] if entry.key?(field) }
  end

  def render_catalog
    response.headers['Cache-Control'] = 'no-store'
    render json: base_payload.merge(item: catalog.call)
  end

  def render_invalid_catalog(error)
    render json: base_payload.merge(error: error.code, invalid_attributes: error.fields), status: error.status
  end
end

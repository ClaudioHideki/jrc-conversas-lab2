class Api::V1::Accounts::Customers::ContactSigningIdentitiesController < Api::V1::Accounts::Customers::BaseController
  rescue_from JrcCustomers::SigningIdentityWriter::Changed do
    render json: { code: 'IDENTITY_CHANGED' }, status: :conflict
  end
  rescue_from ActiveRecord::Encryption::Errors::Decryption do
    render json: { code: 'IDENTITY_UNAVAILABLE' }, status: :unprocessable_entity
  end
  after_action { response.headers['Cache-Control'] = 'no-store' }

  def show
    contact = directory.find(params[:contact_id])
    record = JrcCustomers::SigningIdentity.find_by(account_id: Current.account.id, contact_id: contact.id)
    present(contact, record)
  end

  def update
    record = JrcCustomers::SigningIdentityWriter.new(account: Current.account, actor: Current.user).save!(
      contact_id: params[:contact_id], personal_tax_identifier: params.require(:identity).permit(:personal_tax_identifier)[:personal_tax_identifier],
      expected_revision: params.require(:revision)
    )
    present(directory.find(params[:contact_id]), record)
  end

  private

  def directory
    JrcCustomers::ContactDirectory.new(account: Current.account, actor: Current.user)
  end

  def present(contact, record)
    identifier = record&.personal_tax_identifier
    directory.find(contact.id) # Reauthorize after decrypting protected data.
    render json: { contact: serializer.contact(contact), payload: {
      revision: record&.revision || 0, personal_tax_identifier: identifier,
      personal_tax_identifier_masked: record&.masked_identifier, signing_authority_verified: false
    } }
  end
end

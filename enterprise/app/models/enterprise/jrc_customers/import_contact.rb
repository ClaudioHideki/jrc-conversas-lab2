module Enterprise::JrcCustomers::ImportContact
  extend ActiveSupport::Concern

  included do
    # A reviewed CSV company link must not be replaced by email-domain guessing.
    skip_callback :commit, :after, :associate_company_from_email
  end
end

class JrcCustomers::CompanyWriter
  class StaleRevision < StandardError; end
  def initialize(account:, actor:)
    @account = account
    @actor = actor
  end

  def save!(company:, attributes:, expected_revision: nil)
    raise ActiveRecord::RecordNotFound unless company.account_id == @account.id

    # Serializes hierarchy changes and makes the audit part of the same commit.
    @account.with_lock do
      company.reload if company.persisted?
      if expected_revision && company.updated_at&.iso8601(6) != expected_revision
        raise StaleRevision, 'This company changed since it was opened. Reload before saving.'
      end
      previous = company.attributes.slice(*attributes.keys.map(&:to_s))
      created = company.new_record?
      company.assign_attributes(attributes)
      company.save!
      JrcCustomers::Audit.record!(account: @account, actor: @actor, resource: company,
                                  event_type: created ? 'customer_company_created' : 'customer_company_updated',
                                  from_value: previous, to_value: company.attributes.slice(*attributes.keys.map(&:to_s)))
      company
    end
  end
end

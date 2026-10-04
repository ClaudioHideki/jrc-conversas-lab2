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

      attributes = attributes.to_h.symbolize_keys
      created = company.new_record?
      if @actor && company.has_attribute?(:updated_by_id)
        attributes[:updated_by_id] = @actor.id
        attributes[:created_by_id] = @actor.id if created && company.created_by_id.blank?
      end

      audited_keys = attributes.keys.map(&:to_s)
      previous = company.attributes.slice(*audited_keys)
      company.assign_attributes(attributes)
      company.save!
      assign_customer_code!(company)

      JrcCustomers::Audit.record!(
        account: @account,
        actor: @actor,
        resource: company,
        event_type: created ? 'customer_company_created' : 'customer_company_updated',
        from_value: previous,
        to_value: company.attributes.slice(*(audited_keys + ['customer_code']).uniq)
      )
      company
    end
  end

  private

  def assign_customer_code!(company)
    return unless company.has_attribute?(:customer_code) && company.customer_code.blank?

    company.update_column(:customer_code, format('EMP-%06d', company.id))
  end
end

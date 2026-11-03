class Companies::DeleteJob < ApplicationJob
  queue_as :low

  BATCH_SIZE = 1000
  CONTACT_COMPANY_CLEAR_SQL = <<~SQL.squish.freeze
    company_id = NULL,
    job_title = NULL,
    department = NULL,
    company_role = NULL,
    company_primary = FALSE,
    company_contact_status = 'active',
    additional_attributes = COALESCE(additional_attributes, '{}'::jsonb) - 'company_name'
  SQL

  def perform(company_id:)
    company = Company.find_by(id: company_id)
    return if company.blank?

    # Share the master writers' lock order; a failed delete must retain every link.
    company.account.with_lock do
      company = Company.lock.find_by(id: company_id, account_id: company.account_id)
      next unless company

      if Contact.where(company_id: company.id).where.not(account_id: company.account_id).exists?
        raise ActiveRecord::InvalidForeignKey, 'Company has contacts from another account'
      end

      clear_contact_company_names(company)
      company.destroy!
    end
  end

  private

  # Avoid contact callbacks so this cleanup does not dispatch contact automations/webhooks.
  # rubocop:disable Rails/SkipsModelValidations
  def clear_contact_company_names(company)
    company.account.contacts.where(company_id: company.id).in_batches(of: BATCH_SIZE) do |contacts|
      previous = contacts.lock.to_a
      contacts.update_all(CONTACT_COMPANY_CLEAR_SQL)
      previous.each do |contact|
        JrcCustomers::Audit.record!(
          account: company.account, actor: nil, resource: contact, event_type: 'customer_contact_linked',
          metadata: { reason: 'company_deleted' },
          from_value: contact.attributes.slice(*JrcCustomers::ContactMaster::COMPANY_CONTEXT_FIELDS),
          to_value: contact.reload.attributes.slice(*JrcCustomers::ContactMaster::COMPANY_CONTEXT_FIELDS)
        )
      end
    end
  end
  # rubocop:enable Rails/SkipsModelValidations
end

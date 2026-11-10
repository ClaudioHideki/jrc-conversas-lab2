class JrcCustomers::EconomicGroupWriter
  def initialize(account:, actor:)
    @account = account
    @actor = actor
    @directory = JrcCustomers::EconomicGroupDirectory.new(account: account, actor: actor)
  end

  def save!(group:, attributes:, expected_revision: nil)
    @account.with_lock do
      authorize_configuration!
      prepare!(group, expected_revision)
      raise ActiveRecord::RecordNotFound unless @directory.complete_coverage?(group)

      created = group.new_record?
      previous = group.attributes.slice('name', 'description', 'principal_company_id')
      values = attributes.to_h.stringify_keys.slice('name', 'description', 'principal_company_id')
      @directory.companies.find(values['principal_company_id']) if values['principal_company_id'].present?
      group.update!(values)
      audit!(group, created ? 'customer_economic_group_created' : 'customer_economic_group_updated', previous)
      group
    end
  end

  def assign!(group:, company_id:, revision:, remove: false, confirm_transfer: false)
    @account.with_lock do
      prepare!(group)
      company = @directory.companies.find(company_id)
      validate_transfer!(company, group, remove: remove, confirmed: confirm_transfer)
      JrcCustomers::CompanyWriter.new(account: @account, actor: @actor).save!(
        company: company, attributes: { economic_group: remove ? nil : group.name }, expected_revision: revision
      )
      group.update!(updated_at: Time.current)
      audit!(group, 'customer_economic_group_linked', nil, company_id: company.id, operation: remove ? 'remove' : 'assign')
      company
    end
  end

  def destroy!(group:, expected_revision:)
    @account.with_lock do
      authorize_configuration!
      prepare!(group, expected_revision)
      if group.companies.exists? || group.principal_company_id.present? || group.criteria_dependents?
        group.errors.add(:base, 'Remove member companies, principal and saved criteria before deleting the group')
        raise ActiveRecord::RecordInvalid, group
      end
      audit!(group, 'customer_economic_group_deleted')
      group.destroy!
    end
  end

  private

  def validate_transfer!(company, group, remove:, confirmed:)
    raise JrcCustomers::CompanyWriter::StaleRevision, 'Company is no longer a member of this group' if remove && company.economic_group != group.name

    return if remove || company.economic_group.blank? || company.economic_group == group.name || confirmed

    raise JrcCustomers::MergePreserver::Conflict, 'Confirm transfer from the current economic group'
  end

  def prepare!(group, revision = nil)
    raise ActiveRecord::RecordNotFound unless group.account_id == @account.id

    if group.persisted?
      @directory.scope.find(group.id)
      group.reload
    else
      JrcCustomers::ContactDirectory.new(account: @account, actor: @actor).authorize!
    end
    return unless revision && group.updated_at&.iso8601(6) != revision

    raise JrcCustomers::CompanyWriter::StaleRevision, 'Economic group changed; reload before saving'
  end

  def authorize_configuration!
    JrcCustomers::ContactDirectory.new(account: @account, actor: @actor).authorize!
    member = AccountUser.find_by!(account_id: @account.id, user_id: @actor.id)
    context = { account: @account, user: @actor, account_user: member }
    raise Pundit::NotAuthorizedError unless JrcCustomers::DirectoryPolicy.new(context, :directory).administer?
  end

  def audit!(group, event, previous = nil, metadata = {})
    JrcCustomers::Audit.record!(account: @account, actor: @actor, resource: group, event_type: event, metadata: metadata,
                                from_value: previous, to_value: group.attributes.slice('name', 'description', 'principal_company_id'))
  end
end

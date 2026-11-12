class JrcCustomers::ImportContactIdentity
  def initialize(account:, actor:)
    @account = account
    @directory = JrcCustomers::ContactDirectory.new(account: account, actor: actor)
  end

  def find(attributes)
    ids = candidate_ids(attributes)
    if ids.size > 1
      raise JrcCustomers::ImportIssue.new('Conflicting identities; review without merging', field: 'identity', code: 'AMBIGUOUS_CONTACT')
    end
    raise ActiveRecord::RecordNotFound if attributes.values['id'] && ids != [attributes.values['id']]

    ids.empty? ? @account.contacts.new(registration_status: 'registered') : @directory.find(ids.first)
  end

  private

  def candidate_ids(attributes)
    values = attributes.values
    resolver = JrcCustomers::IdentityResolver.new(account: @account, personal_tax_identifier: attributes.personal_identifier)
    matches = resolver.call(email: values['email'], phone: values['phone_number'])
    candidates = @account.contacts.where(id: matches.reselect(:id))
    candidates = candidates.or(@account.contacts.where(identifier: values['identifier'])) if values['identifier']
    candidates = candidates.or(@account.contacts.where(id: values['id'])) if values['id']
    candidates.distinct.limit(51).pluck(:id)
  end
end

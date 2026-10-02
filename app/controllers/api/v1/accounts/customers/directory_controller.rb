class Api::V1::Accounts::Customers::DirectoryController < Api::V1::Accounts::Customers::BaseController
  def metadata
    users = Current.account.users.order(:name).limit(500).pluck(:id, :name).map { |id, name| { id: id, name: name } }
    render json: { relationships: JrcCustomers::CompanyRules::RELATIONSHIPS,
                   person_kinds: JrcCustomers::CompanyRules::PERSON_KINDS,
                   address_types: JrcCustomers::Address::TYPES, contact_point_kinds: JrcCustomers::ContactPoint::KINDS,
                   owners: users, can_administer: Current.account_user.administrator?,
                   external_tax_lookup: { configured: JrcCustomers::TaxLookup.configured?, required: false },
                   segments: Current.account.master_companies.where.not(segment: [nil, '']).distinct.order(:segment).limit(200).pluck(:segment),
                   economic_groups: Current.account.master_companies.where.not(economic_group: [nil, '']).distinct.order(:economic_group).limit(200).pluck(:economic_group) }
  end

  def identity
    matches = JrcCustomers::IdentityResolver.new(account: Current.account).call(email: params[:email], phone: params[:phone],
                                                                                 extension: params[:extension], country: params[:country]).to_a
    render json: { payload: serializer.contacts(matches.first(50)), match: matches.one? ? 'unique' : (matches.empty? ? 'none' : 'ambiguous'),
                   truncated: matches.size > 50, creates_customer: false }
  end
end

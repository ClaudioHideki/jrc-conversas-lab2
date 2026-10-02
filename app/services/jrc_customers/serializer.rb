class JrcCustomers::Serializer
  COMPANY_FIELDS = %w[id name person_kind trade_name tax_id state_registration municipal_registration segment size website domain
                      email phone_number source economic_group parent_company_id owner_id relationship_type active description created_at updated_at].freeze
  CONTACT_FIELDS = %w[id name email phone_number identifier company_id job_title department registration_status contact_type blocked created_at updated_at].freeze

  def initialize(account:)
    @account = account
  end

  def companies(records)
    ids = records.map(&:id)
    counts = @account.contacts.where(company_id: ids).group(:company_id).count
    owners = @account.users.where(id: records.map(&:owner_id).compact).pluck(:id, :name).to_h
    cities = JrcCustomers::Address.where(account_id: @account.id, company_id: ids).order(:id).pluck(:company_id, :city).each_with_object({}) do |(id, city), result|
      result[id] ||= city if city.present?
    end
    records.map do |company|
      company.attributes.slice(*COMPANY_FIELDS).merge('revision' => company.updated_at&.iso8601(6), 'contact_count' => counts.fetch(company.id, 0),
                                                     'owner_name' => owners[company.owner_id], 'city' => cities[company.id])
    end
  end

  def company(record)
    companies([record]).first
  end

  def contacts(records)
    companies = @account.master_companies.where(id: records.map(&:company_id).compact).pluck(:id, :name).to_h
    records.map { |record| record.attributes.slice(*CONTACT_FIELDS).merge('company_name' => companies[record.company_id]) }
  end

  def contact(record)
    contacts([record]).first
  end
end

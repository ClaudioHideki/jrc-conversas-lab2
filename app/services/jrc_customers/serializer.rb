class JrcCustomers::Serializer
  COMPANY_FIELDS = %w[id customer_code name person_kind trade_name tax_id state_registration municipal_registration segment size website domain
                      email phone_number source economic_group parent_company_id owner_id relationship_type relationship_tags tags active description
                      created_by_id updated_by_id last_activity_at created_at updated_at].freeze
  CONTACT_FIELDS = %w[id name email phone_number identifier company_id job_title department registration_status contact_type blocked created_at updated_at].freeze

  def initialize(account:)
    @account = account
  end

  def companies(records)
    ids = records.map(&:id)
    counts = @account.contacts.where(company_id: ids).group(:company_id).count
    user_ids = records.flat_map { |record| [record.owner_id, safe_attribute(record, :created_by_id), safe_attribute(record, :updated_by_id)] }.compact.uniq
    users = @account.users.where(id: user_ids).pluck(:id, :name).to_h
    cities = JrcCustomers::Address.where(account_id: @account.id, company_id: ids).order(:id).pluck(:company_id, :city).each_with_object({}) do |(id, city), result|
      result[id] ||= city if city.present?
    end
    records.map do |company|
      row = company.attributes.slice(*COMPANY_FIELDS)
      row['customer_code'] ||= format('EMP-%06d', company.id)
      row.merge(
        'revision' => company.updated_at&.iso8601(6),
        'contact_count' => counts.fetch(company.id, 0),
        'owner_name' => users[company.owner_id],
        'created_by_name' => users[safe_attribute(company, :created_by_id)],
        'updated_by_name' => users[safe_attribute(company, :updated_by_id)],
        'city' => cities[company.id]
      )
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

  private

  def safe_attribute(record, key)
    record.has_attribute?(key) ? record.public_send(key) : nil
  end
end

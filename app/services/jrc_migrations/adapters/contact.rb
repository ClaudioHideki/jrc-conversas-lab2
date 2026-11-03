class JrcMigrations::Adapters::Contact < JrcMigrations::Adapters::Base
  def model
    ::Contact
  end

  def candidates(data)
    %w[email phone_number identifier].filter_map do |field|
      next if data[field].blank?

      scope.where("LOWER(#{field}) = ?", data[field].to_s.strip.downcase).pick(:id)
    end.uniq
  end

  private

  def resolve_relations!(record, data)
    bind_legacy_reference!(record, data, field: 'company_id', legacy_field: 'company_legacy_id')
    check_company!(record.company_id)
  end

  def prepare(record)
    ::Contacts::SyncAttributes.new(record).perform
    return if record.company_id.blank?

    company = JrcCustomers::Company.find_by!(account_id: account.id, id: record.company_id)
    record.additional_attributes = record.additional_attributes.merge('company_name' => company.name)
  end
end

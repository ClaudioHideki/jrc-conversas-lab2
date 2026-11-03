class JrcMigrations::Adapters::Company < JrcMigrations::Adapters::Base
  def model
    JrcCustomers::Company
  end

  def candidates(data)
    %w[tax_id domain email name].filter_map do |field|
      next if data[field].blank?

      value = field == 'tax_id' ? JrcCustomers::TaxIdentifier.normalize(data[field]) : data[field].to_s.strip.downcase
      scope.where("LOWER(#{field}) = ?", value).pick(:id)
    end.uniq
  end

  private

  def resolve_relations!(record, data)
    bind_legacy_reference!(record, data, field: 'parent_company_id', legacy_field: 'legacy_parent_id')
    check_company!(record.parent_company_id)
    return if record.owner_id.blank? || account.users.exists?(id: record.owner_id)

    raise JrcMigrations::Error, 'RELATION_OUTSIDE_ACCOUNT'
  end
end

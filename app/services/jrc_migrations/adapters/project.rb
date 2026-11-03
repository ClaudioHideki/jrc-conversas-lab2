class JrcMigrations::Adapters::Project < JrcMigrations::Adapters::Base
  def model
    JrcProjects::Project
  end

  def candidates(data)
    data['key'].present? ? scope.where(key: data['key']).limit(1).pluck(:id) : []
  end

  private

  def assignable_attributes
    super + ['priority']
  end

  def resolve_relations!(record, data)
    bind_legacy_reference!(record, data, field: 'contact_id', legacy_field: 'contact_legacy_id', domain: 'contacts')
    bind_legacy_reference!(record, data, field: 'company_id', legacy_field: 'company_legacy_id')
    check_company!(record.company_id)
    %w[archived_at completed_at].each do |field|
      record.public_send("#{field}=", timestamp!(data[field])) if data[field].present?
    end
  end
end

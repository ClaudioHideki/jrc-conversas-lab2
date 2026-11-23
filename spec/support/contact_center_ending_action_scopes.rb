# Native PostgreSQL fixtures only. A recorded scope never grants module or destination permission.
RSpec.shared_context 'with a native ending action queue scope' do
  let(:account) { create(:account) }
  let(:issuer) { JrcCustomers::Company.create!(account: account, name: 'SYNTHETIC issuer', relationship_type: 'internal', active: true) }
  let(:business) do
    JrcCrm::BusinessUnit.create!(account: account, operating_company: issuer, name: 'SYNTHETIC business', code: 'SYNTHETIC', active: true)
  end
  let(:unit) do
    JrcContactCenter::Unit.create!(account: account, code: 'SYNTHETIC', name: 'SYNTHETIC operational', kind: 'sac',
                                   settings: { 'issuer_company_id' => issuer.id, 'business_unit_id' => business.id })
  end
  let(:queue) do
    JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'SYNTHETIC', name: 'SYNTHETIC queue',
                                    service_kind: 'voice', strategy: 'ring_all')
  end
  let(:scopes) { JrcContactCenter::EndingActionQueueScope.where(account: account, source_queue_id: queue.id).order(:revision) }
  let(:scope) { scopes.last }

  def guarded_ending_scope_sql(statement)
    ApplicationRecord.transaction(requires_new: true) { ApplicationRecord.connection.execute(statement) }
  end

  # Intentional direct SQL tests the database boundary rather than skipping a model validation in application code.
  def write_ending_scope_settings(values)
    encoded = ApplicationRecord.connection.quote(values.to_json)
    guarded_ending_scope_sql("UPDATE jrc_contact_center_units SET settings=#{encoded}::jsonb WHERE id=#{unit.id}")
    unit.reload
  end
end

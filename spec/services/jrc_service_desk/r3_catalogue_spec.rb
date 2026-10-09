# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk::TicketCatalogue do
  include_context 'JRC Service Desk domain'
  let(:field) { { 'key' => 'circuit', 'label' => 'Circuit', 'type' => 'text', 'required' => true } }
  let(:type) { JrcServiceDesk::TicketType.create!(account: sd_account, unit: sd_unit, name: 'Request', code: 'request', active: true) }
  let(:category) { create(:jrc_sd_category, unit: sd_unit, form_fields: [field]) }
  let(:subcategory) { create(:jrc_sd_category, unit: sd_unit, parent: category) }
  let(:service) do
    JrcServiceDesk::Service.create!(account: sd_account, unit: sd_unit, name: 'Circuit support', code: 'circuit', active: true,
                                    default_priority: sd_priority, default_category: category, default_ticket_type: type)
  end
  let(:command) { JrcServiceDesk::CreateTicketService.new(user_context: sd_context) }

  before { sd_as_admin! }

  it 'persists service/type/category defaults and dynamic answers with immutable configuration revisions' do
    ticket = command.call(unit_id: sd_unit.id, service_id: service.id, idempotency_key: 'r3-defaults',
                          attributes: sd_create_attributes.merge(service_fields: { 'circuit' => 'LOCAL-42' }))
    loaded = JrcServiceDesk::Ticket.find(ticket.id)
    expect(loaded.attributes.values_at('ticket_type_id', 'category_id')).to eq([type.id, category.id])
    expect(loaded.catalogue_snapshot.fetch('form_fields')).to eq([field])
    revision = loaded.catalogue_snapshot.fetch('service_revision')
    service.update!(name: 'Renamed catalogue')
    expect(loaded.reload.catalogue_snapshot.fetch('service_revision')).to eq(revision)
    expect(loaded.service_fields).to eq('circuit' => 'LOCAL-42')
  end

  it 'rejects missing required answers without persisting a ticket or an event' do
    expect do
      command.call(unit_id: sd_unit.id, service_id: service.id, idempotency_key: 'r3-required', attributes: sd_create_attributes)
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(JrcServiceDesk::Ticket.where(idempotency_key: 'r3-required')).not_to exist
  end

  it 'rejects a subcategory from another root or unit and preserves both catalogues' do
    service
    other = create(:jrc_sd_category, unit: sd_unit)
    expect do
      command.call(unit_id: sd_unit.id, service_id: service.id, idempotency_key: 'r3-parent',
                   attributes: sd_create_attributes.merge(category_id: other.id, subcategory_id: subcategory.id,
                                                          service_fields: { 'circuit' => 'LOCAL' }))
    end.to raise_error(ActiveRecord::RecordInvalid)
    foreign_type = JrcServiceDesk::TicketType.create!(account: sd_account, unit: sd_other_unit, name: 'Foreign unit', code: 'foreign', active: true)
    expect do
      command.call(unit_id: sd_unit.id, idempotency_key: 'r3-foreign-type', attributes: sd_create_attributes.merge(ticket_type_id: foreign_type.id))
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'reads composed fields by explicit IDs beyond lookup pagination and rejects duplicate keys' do
    result = JrcServiceDesk::CatalogueForm.new(user_context: sd_context).call(parameters: { unit_id: sd_unit.id, service_id: service.id })
    expect(result.values_at(:form_fields, :ticket_type, :category)).to eq(
      [[field], { id: type.id.to_s, name: type.name }, { id: category.id.to_s, name: category.name }]
    )
    type.update!(form_fields: [field])
    expect do
      JrcServiceDesk::CatalogueForm.new(user_context: sd_context).call(parameters: { unit_id: sd_unit.id, service_id: service.id })
    end.to raise_error(ArgumentError, 'Conflicting catalogue fields')
  end

  it 'preserves explicit clears instead of silently reapplying defaults during edit' do
    ticket = command.call(unit_id: sd_unit.id, service_id: service.id, idempotency_key: 'r3-clear',
                          attributes: sd_create_attributes.merge(service_fields: { 'circuit' => 'LOCAL' }))
    JrcServiceDesk::UpdateTicketService.new(user_context: sd_context).call(
      ticket_id: ticket.id, expected_lock_version: ticket.lock_version,
      attributes: { ticket_type_id: nil, category_id: nil, service_fields: {} }
    )
    expect(ticket.reload.attributes.values_at('ticket_type_id', 'category_id', 'service_fields')).to eq([nil, nil, {}])
  end

  it 'rejects foreign canonical restrictions at model and authorized configuration boundaries' do
    foreign = JrcCustomers::Company.create!(account: sd_foreign_account, name: 'Foreign canonical company')
    expect { service.update!(allowed_company_ids: [foreign.id]) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(service.reload.allowed_company_ids).to eq([])
  end

  it 'retains explicit expiry timestamps in canonical revisions and native audits' do
    result = JrcServiceDesk::ConfigurationService.new(user_context: sd_context).create(
      resource: 'services', unit_id: sd_unit.id, idempotency_key: 'r3-expiry',
      attributes: { name: 'Expiring portal', code: 'expiry', active: false, portal_access_until: '2030-01-02T12:00:00-03:00' }
    )
    expect(JrcServiceDesk::ConfigurationResources.fields('services', result.record)['portal_access_until']).to eq('2030-01-02T15:00:00.000000Z')
    expect(JSON.parse(Audited::Audit.find(result.audit_id).comment).dig('after', 'portal_access_until')).to eq('2030-01-02T15:00:00.000000Z')
  end
end

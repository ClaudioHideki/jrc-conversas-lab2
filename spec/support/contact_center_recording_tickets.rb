# frozen_string_literal: true

# All grants and mappings below belong to disposable synthetic test records only.
RSpec.shared_context 'with native manual recording ticket intake' do
  include_context 'with native authorized quality review source'
  include_context 'JRC Service Desk domain'

  let(:sd_account) { account }
  let(:sd_user) { actor }
  let(:sd_account_user) { member }
  let(:sd_contact) { create(:contact, account: account, name: 'SYNTHETIC explicitly linked caller') }
  let(:ticket_key) { SecureRandom.uuid }
  let(:ticket_input) do
    { 'unit_id' => sd_unit.id.to_s, 'recording_id' => record.id.to_s,
      'ticket' => { 'title' => 'SYNTHETIC manual recording ticket', 'description' => 'SYNTHETIC private description',
                    'requester_id' => sd_contact.id.to_s, 'status_id' => sd_status.id.to_s, 'priority_id' => sd_priority.id.to_s } }
  end

  before do
    account.enable_features!('jrc_customer_master')
    rights = %w[contact_manage jrc_contact_center_operate jrc_service_desk_module_view jrc_service_desk_tickets_view
                jrc_service_desk_tickets_create jrc_service_desk_lookups_view jrc_service_desk_customers_view]
    role.update!(permissions: (role.permissions + rights).uniq)
    account.jrc_crm_user_business_units.where(user: actor).find_each(&:destroy!)
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'GROUP', active: true, structure_managed: true)
    business.update!(settings: business.settings.merge('service_desk_unit_id' => sd_unit.id.to_s))
    source_call.update!(contact_id: sd_contact.id, company_id: sd_contact.company_id)
  end
end

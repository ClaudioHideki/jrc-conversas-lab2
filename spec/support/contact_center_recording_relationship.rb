# frozen_string_literal: true

# Explicit synthetic grants, mappings and native portfolios only. No PABX I/O.
RSpec.shared_context 'with native recording Relationship intake' do
  include_context 'with native authorized quality review source'

  let(:customer) { account.master_companies.create!(name: 'SYNTHETIC Relationship recording customer') }
  let(:caller_contact) { create(:contact, account: account, company_id: customer.id, name: 'SYNTHETIC linked recording caller') }
  let(:assignment) do
    JrcRelationship::Assignment.create!(account: account, company: customer, owner: actor, business_unit: business, status: 'active')
  end
  let(:relationship_key) { SecureRandom.uuid }
  let(:relationship_input) do
    { 'assignment_id' => assignment.id.to_s, 'request_id' => relationship_key, 'origin_revision' => origin_preview.fetch(:origin_revision),
      'title' => 'SYNTHETIC reviewed recording follow-up', 'due_at' => '2026-12-18T15:30:00Z' }
  end
  let(:origin_preview) do
    JrcContactCenter::RecordingRelationshipScope.new(account: account, member: member).preview(record.id)
  end

  before do
    account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    rights = %w[contact_manage jrc_contact_center_operate jrc_relationship_view jrc_relationship_manage jrc_crm]
    role.update!(permissions: (role.permissions + rights).uniq)
    member.update!(crm_enabled: true)
    account.jrc_crm_user_business_units.where(user: actor).find_each(&:destroy!)
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'GROUP', active: true, structure_managed: true)
    source_call.update!(contact: caller_contact, company: customer)
    assignment
  end
end

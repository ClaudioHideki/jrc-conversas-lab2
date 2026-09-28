# frozen_string_literal: true

# Loaded as a named shared context only; no data is created outside an including spec.
RSpec.shared_context 'JRC Service Desk domain' do
  let(:sd_account) { create(:account) }
  let(:sd_operator) { create(:jrc_sd_operator_company, account: sd_account) }
  let(:sd_unit) { create(:jrc_sd_unit, operator_company: sd_operator) }
  let(:sd_other_unit) { create(:jrc_sd_unit, operator_company: sd_operator) }
  let(:sd_user) { create(:user) }
  let(:sd_account_user) { create(:account_user, account: sd_account, user: sd_user, role: :agent) }
  let(:sd_membership) { create(:jrc_sd_membership, unit: sd_unit, account_user: sd_account_user) }
  let(:sd_contact) { create(:contact, account: sd_account) }
  let(:sd_status) { create(:jrc_sd_status, unit: sd_unit) }
  let(:sd_priority) { create(:jrc_sd_priority, unit: sd_unit) }
  let(:sd_context) { { account: sd_account, user: sd_user, account_user: sd_account_user } }
  let(:sd_foreign_account) { create(:account) }
  let(:sd_foreign_operator) { create(:jrc_sd_operator_company, account: sd_foreign_account) }
  let(:sd_foreign_unit) { create(:jrc_sd_unit, operator_company: sd_foreign_operator) }

  before do
    sd_account.enable_features!('jrc_service_desk')
    sd_membership
  end

  def sd_ticket(overrides = {})
    create(:jrc_sd_ticket, **{ account: sd_account, unit: sd_unit, requester: sd_contact,
                              status: sd_status, priority: sd_priority, created_by_membership: sd_membership }.merge(overrides))
  end

  def sd_create_attributes
    { title: 'Created through CP2 service', description: 'Database test only', requester_id: sd_contact.id,
      status_id: sd_status.id, priority_id: sd_priority.id }
  end

  def sd_snapshot_attributes
    { source_system: 'test-provider', source_reference: 'test-contract', source_version: 'v1',
      contract_conditions: { coverage: 'test' }, policy_key: 'test-policy', policy_version: 'v1',
      policy_conditions: { first_response_seconds: 300 }, calendar_key: 'test-calendar', calendar_version: 'v1',
      calendar_scope: 'unit', calendar_conditions: { weekdays: [1, 2, 3, 4, 5], holidays: [], exceptions: [] },
      timezone: 'America/Sao_Paulo', captured_at: '2026-09-25T10:00:00Z' }
  end

  def sd_as_admin!
    sd_account_user.update!(role: :administrator)
  end
end

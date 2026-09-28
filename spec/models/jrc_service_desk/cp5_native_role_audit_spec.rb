# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'CP5 native role audit integration' do
  include_context 'JRC Service Desk domain'

  before do
    skip 'Native CustomRole/AuditLog extension unavailable' unless defined?(::CustomRole) && defined?(::Enterprise::AuditLog)
    Current.user = sd_user
  end
  after { Current.reset }

  it 'records granting and revoking Service Desk capabilities with native author and Account' do
    role = CustomRole.create!(account: sd_account, name: 'Audited SD role', permissions: ['jrc_service_desk_module_view'])
    role.update!(permissions: [])
    entries = Enterprise::AuditLog.where(auditable_type: 'CustomRole', auditable_id: role.id).order(:id)
    expect(entries.count).to eq(2)
    expect(entries.last.associated_id).to eq(sd_account.id)
    expect(entries.last.user_id).to eq(sd_user.id)
    expect(entries.last.audited_changes['permissions']).to eq([['jrc_service_desk_module_view'], []])
    expect(entries.last.created_at).to be_present
  end

  it 'does not create a Service Desk audit event for unchanged legacy-only permissions' do
    role = CustomRole.create!(account: sd_account, name: 'Legacy-only role', permissions: ['contact_manage'])
    role.update!(permissions: ['report_manage'])
    expect(Enterprise::AuditLog.where(auditable_type: 'CustomRole', auditable_id: role.id)).to be_empty
  end
end

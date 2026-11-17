require 'rails_helper'

RSpec.describe 'Call Center native capability audit', type: :model do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:audits) { Enterprise::AuditLog.where(comment: 'JRC Call Center native capabilities', associated: account) }

  around do |example|
    previous = [Current.user, Current.account]
    Current.user = actor
    Current.account = account
    example.run
  ensure
    Current.user, Current.account = previous
  end

  it 'records only Call Center capabilities with actor and Account on create and update' do
    role = create(:custom_role, account: account, permissions: %w[contact_manage jrc_contact_center_view])
    audit = audits.last
    expect(audit.user_id).to eq(actor.id)
    expect(audit.auditable_id).to eq(role.id)
    expect(audit.audited_changes).to eq('permissions' => [[], ['jrc_contact_center_view']])

    role.update!(permissions: %w[contact_manage jrc_contact_center_view jrc_contact_center_monitor])
    expect(audits.last.audited_changes).to eq(
      'permissions' => [['jrc_contact_center_view'], %w[jrc_contact_center_monitor jrc_contact_center_view]]
    )
  end

  it 'does not audit unrelated permissions, no-ops, names or descriptions' do
    role = create(:custom_role, account: account, permissions: %w[contact_manage jrc_contact_center_view])
    expect do
      role.update!(permissions: %w[report_manage jrc_contact_center_view], description: 'Private text not copied')
      role.update!(name: 'Renamed')
      role.update!(permissions: role.permissions)
    end.not_to change(audits, :count)
    expect(audits.last.audited_changes.to_json).not_to include('Private text', 'report_manage', 'contact_manage')
  end

  it 'keeps failed changes and rolled back changes out of the audit history' do
    role = create(:custom_role, account: account, permissions: ['jrc_contact_center_view'])
    expect do
      expect(role.update(name: nil, permissions: [])).to be(false)
      role.reload
      CustomRole.transaction do
        role.update!(permissions: [])
        raise ActiveRecord::Rollback
      end
    end.not_to change(audits, :count)
    expect(role.reload.permissions).to eq(['jrc_contact_center_view'])
  end

  it 'records destruction in the original Account and keeps other Account history separate' do
    role = create(:custom_role, account: account, permissions: ['jrc_contact_center_view'])
    other = create(:account)
    create(:custom_role, account: other, permissions: ['jrc_contact_center_publish'])
    expect { role.destroy! }.to change(audits, :count).by(1)
    expect(audits.last.action).to eq('destroy')
    expect(audits.last.audited_changes).to eq('permissions' => [['jrc_contact_center_view'], []])
    expect(audits.pluck(:auditable_id)).to all(eq(role.id))
  end
end

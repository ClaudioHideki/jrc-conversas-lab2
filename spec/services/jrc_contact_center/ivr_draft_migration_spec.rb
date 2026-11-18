require 'rails_helper'
require Rails.root.join('db/migrate/20261117200000_create_contact_center_ivr_drafts')

RSpec.describe 'Local IVR ledger populated upgrade', type: :model do
  let(:account) { create(:account) }
  let(:operator) { create(:user, :contact_center_eligible, account: account) }
  let(:member) { account.account_users.find_by!(user: operator) }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, code: 'EXISTING', name: 'SYNTHETIC pre-upgrade unit', kind: 'sac') }
  let(:migration) { CreateContactCenterIvrDrafts.new }
  let(:definition) { { 'schema_version' => 1, 'start' => 'end', 'nodes' => [{ 'id' => 'end', 'type' => 'end' }] } }

  before do
    owned = Rails.env.test? && ActiveRecord::Base.connection.current_database == 'jrc_sd_bc_portal_concurrency_20261025_test'
    raise 'Owned synthetic migration database required' unless owned
  end

  it 'adds only empty ledger tables without changing existing unit, member or eligibility data' do
    before = [unit.attributes, member.attributes, JrcContactCenter::AccessGrant.find_by!(account_user: member).attributes]
    connection = ActiveRecord::Base.connection
    connection.drop_table(:jrc_contact_center_ivr_draft_versions)
    connection.drop_table(:jrc_contact_center_ivr_drafts)
    %w[cc_ivr_draft_guard cc_ivr_version_guard cc_ivr_first_version_guard].each do |function|
      connection.execute("DROP FUNCTION #{function}()")
    end
    migration.up
    expect([unit.reload.attributes, member.reload.attributes, JrcContactCenter::AccessGrant.find_by!(account_user: member).attributes]).to eq(before)
    expect(JrcContactCenter::IvrDraft.count).to eq(0)
    expect(JrcContactCenter::IvrDraftVersion.count).to eq(0)
    expect(connection.foreign_keys(:jrc_contact_center_ivr_drafts).length).to eq(2)
    expect(connection.foreign_keys(:jrc_contact_center_ivr_draft_versions).length).to eq(2)
  end

  it 'reexecutes against populated history without inserting, mutating or reauthorizing anything' do
    draft = JrcContactCenter::IvrDraft.transaction do
      row = JrcContactCenter::IvrDraft.create!(account: account, unit: unit, scope_snapshot: {})
      JrcContactCenter::IvrDraftVersion.create!(account: account, ivr_draft: row, revision: 1, name: 'SYNTHETIC existing',
                                                status: 'draft', definition: definition, request_id: SecureRandom.uuid,
                                                actor_account_user_id: member.id, actor_user_id: operator.id)
      row.reload
    end
    JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(eligible: false)
    before = [draft.attributes, draft.latest_version.reload.attributes]
    migration.up
    migration.up
    expect([draft.reload.attributes, draft.latest_version.reload.attributes]).to eq(before)
    expect(draft.versions.count).to eq(1)
    expect(JrcContactCenter::AccessGrant.find_by!(account_user: member).eligible).to be(false)
  end

  it 'blocks reexecution if a required SQL guard is missing rather than silently repairing an unknown schema' do
    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      ALTER TRIGGER cc_ivr_version_guard ON jrc_contact_center_ivr_draft_versions RENAME TO unexpected_guard
    SQL
    expect { migration.up }.to raise_error(ActiveRecord::MigrationError, /Unexpected IVR ledger schema; review before reexecution/)
  end
end

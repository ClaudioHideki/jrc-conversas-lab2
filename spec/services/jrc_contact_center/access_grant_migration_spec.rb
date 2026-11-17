require 'rails_helper'
require Rails.root.join('db/migrate/20261117190000_add_contact_center_access_grants')

RSpec.describe 'Call Center access grant populated upgrade', type: :model do
  let(:account) { create(:account) }
  let(:old_user) { create(:user, account: account) }
  let(:old_member) { account.account_users.find_by!(user: old_user) }
  let(:migration) { AddContactCenterAccessGrants.new }

  it 'preserves only existing memberships and never backfills a new pending user on reexecution' do
    owned = Rails.env.test? && ActiveRecord::Base.connection.current_database == 'jrc_sd_bc_portal_concurrency_20261025_test'
    raise 'Owned synthetic migration database required' unless owned

    old_member
    connection = ActiveRecord::Base.connection
    connection.drop_table(:jrc_contact_center_access_grants)
    migration.up
    JrcContactCenter::AccessGrant.reset_column_information
    preserved = JrcContactCenter::AccessGrant.find_by!(account_user: old_member)
    expect(preserved.eligible).to be(true)
    expect(preserved.allowed).to eq([])
    preserved.update!(eligible: false)
    pending = create(:user, account: account)
    pending_link = account.account_users.find_by!(user: pending)
    migration.up
    expect(preserved.reload.eligible).to be(false)
    expect(JrcContactCenter::AccessGrant.exists?(account_user: pending_link)).to be(false)
    expect(connection.foreign_keys(:jrc_contact_center_access_grants).length).to eq(3)
    expect(connection.check_constraints(:jrc_contact_center_access_grants).length).to eq(4)
  ensure
    JrcContactCenter::AccessGrant.reset_column_information
  end
end

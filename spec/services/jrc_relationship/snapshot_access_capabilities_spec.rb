require 'rails_helper'

RSpec.describe JrcRelationship::SnapshotAccess do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: user) }
  let(:context) { JrcRelationship::Context.new(member) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: user) }
  let(:attributes) do
    { account: account, assignment: assignment, viewer: user, score: 50, band: 'risk', factors: [], calculated_at: Time.current,
      config_scope_key: 'account', config_version: 1, access_signature: context.access_signature, fingerprint: SecureRandom.hex(16) }
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'rejects formerly enabled CRM evidence after revocation even with empty source arrays' do
    snapshot = JrcRelationship::HealthSnapshot.create!(**attributes, signals: { '_source_ids' => {}, 'capabilities' => { 'crm' => true } })
    rows = JrcRelationship::HealthSnapshot.where(account: account, assignment: assignment, viewer: user)
    expect(described_class.scope(context, rows)).to exist(id: snapshot.id)
    account.disable_features!('jrc_crm')
    expect(described_class.scope(JrcRelationship::Context.new(member), rows)).to be_empty
  end

  it 'does not authorize an empty Service Desk measurement without current native module access' do
    JrcRelationship::HealthSnapshot.create!(**attributes, signals: { '_source_ids' => {}, 'capabilities' => { 'service_desk' => true } })
    rows = JrcRelationship::HealthSnapshot.where(account: account, assignment: assignment, viewer: user)
    expect(described_class.scope(context, rows)).to be_empty
  end

  it 'preserves authorized legacy history without rewriting its immutable evidence or requiring invented source facts' do
    snapshot = JrcRelationship::HealthSnapshot.create!(**attributes, signals: { '_source_ids' => {} })
    captured = snapshot.attributes.deep_dup
    rows = JrcRelationship::HealthSnapshot.where(account: account, assignment: assignment, viewer: user)
    expect(described_class.scope(context, rows)).to exist(id: snapshot.id)
    expect(snapshot.reload.attributes).to eq(captured)
  end

  it 'does not let the optional legacy-manifest branch bypass a known revoked capability' do
    JrcRelationship::HealthSnapshot.create!(**attributes, signals: { 'capabilities' => { 'crm' => true } })
    rows = JrcRelationship::HealthSnapshot.where(account: account, assignment: assignment, viewer: user)
    expect(described_class.scope(context, rows, require_manifest: false)).not_to be_empty
    account.disable_features!('jrc_crm')
    expect(described_class.scope(JrcRelationship::Context.new(member), rows, require_manifest: false)).to be_empty
  end
end

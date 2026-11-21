require 'rails_helper'

RSpec.describe JrcContactCenter::TeamSupervision do
  let(:account) { create(:account) }
  let(:user) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: user) }
  let(:team) { create(:team, account: account) }
  let(:context) { { account: account, account_user: member, user: user } }
  let(:attributes) { { account: account, team: team, account_user: member, kind: 'primary' } }

  before do
    account.enable_features!('jrc_contact_center', 'audit_logs')
    grant = JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member)
    grant.update!(allowed: grant.allowed - ['jrc_contact_center_quality_review'])
  end

  %i[agent administrator].each do |role|
    it "keeps #{role} metadata separate from native memberships, queue participation and all existing permissions" do
      attributes
      member.update!(role: role)
      permissions = JrcContactCenter::ModulePolicy.new(context, :contact_center).effective_permissions
      counts = [TeamMember.count, JrcContactCenter::QueueMembership.count, JrcContactCenter::AccessGrant.count]
      record = described_class.create!(attributes)
      expect(record).to be_persisted
      expect([TeamMember.count, JrcContactCenter::QueueMembership.count, JrcContactCenter::AccessGrant.count]).to eq(counts)
      expect(JrcContactCenter::ModulePolicy.new(context, :contact_center).effective_permissions).to eq(permissions)
      expect(JrcContactCenter::ModulePolicy.new(context, :contact_center)).not_to be_quality_review
      expect(team.team_members).to be_empty
    end
  end

  it 'does not invent a primary when only an additional supervisor has been explicitly saved' do
    record = described_class.create!(attributes.merge(kind: 'additional'))
    expect(record.reload.kind).to eq('additional')
    expect(described_class.where(team: team, kind: 'primary')).to be_empty
  end

  it 'allows the same account member to supervise several native teams without copying that member' do
    first = described_class.create!(attributes)
    second = described_class.create!(attributes.merge(team: create(:team, account: account)))
    expect([first.account_user_id, second.account_user_id]).to eq([member.id, member.id])
    expect(TeamMember.where(user: user)).to be_empty
  end

  it 'rejects a foreign team and foreign member before writing operational metadata' do
    foreign = create(:account)
    foreign_user = create(:user, account: foreign)
    foreign_member = foreign.account_users.find_by!(user: foreign_user)
    wrong_team = described_class.new(attributes.merge(team: create(:team, account: foreign)))
    wrong_member = described_class.new(attributes.merge(account_user: foreign_member))
    expect(wrong_team).not_to be_valid
    expect(wrong_member).not_to be_valid
  end

  it 'does not allow two primary supervisors or duplicate roles for one person in the same team' do
    described_class.create!(attributes)
    other_user = create(:user, account: account)
    other_member = account.account_users.find_by!(user: other_user)
    expect(described_class.new(attributes.merge(account_user: other_member))).not_to be_valid
    expect(described_class.new(attributes.merge(kind: 'additional'))).not_to be_valid
  end

  it 'records before and after metadata with account scope in the native configuration audit' do
    record = described_class.create!(attributes)
    record.update!(kind: 'additional')
    audit = Audited.audit_class.where(auditable_type: described_class.name, auditable_id: record.id, action: 'update').sole
    expect(audit.associated_id).to eq(account.id)
    expect(audit.audited_changes.fetch('attributes').map { |row| row.fetch('kind') }).to eq(%w[primary additional])
    boundary = { 'account_id' => account.id.to_s }
    expect(audit.audited_changes.fetch('cc_scope')).to eq('before' => boundary, 'after' => boundary)
    expect(audit.audited_changes.fetch('omitted_fields')).to be_empty
  end

  it 'retains an explicit removal audit inside native team deletion rather than losing it to SQL cascade alone' do
    record = described_class.create!(attributes)
    team.destroy!
    audit = Audited.audit_class.where(auditable_type: described_class.name, auditable_id: record.id, action: 'destroy').sole
    expect(described_class.exists?(record.id)).to be(false)
    expect(audit.audited_changes.fetch('attributes').first.fetch('team_id')).to eq(team.id)
    expect(audit.audited_changes.fetch('attributes').last).to be_nil
  end

  it 'clears only this new operational metadata when the native account membership is deleted' do
    record = described_class.create!(attributes)
    member.destroy!
    expect(described_class.exists?(record.id)).to be(false)
    expect(Team.exists?(team.id)).to be(true)
    expect(Audited.audit_class.where(auditable_type: described_class.name, auditable_id: record.id, action: 'destroy')).to exist
  end

  it 'rolls back native team deletion and metadata removal when the actual configuration audit callback fails' do
    record = described_class.create!(attributes)
    allow(JrcContactCenter::ConfigurationAudit).to receive(:write!).and_wrap_original do |original, target, **options|
      raise 'SYNTHETIC audit refusal' if target.is_a?(described_class) && options[:action] == 'destroy'

      original.call(target, **options)
    end
    expect { team.destroy! }.to raise_error(RuntimeError, 'SYNTHETIC audit refusal')
    expect(Team.exists?(team.id)).to be(true)
    expect(described_class.find(record.id).kind).to eq('primary')
    expect(Audited.audit_class.where(auditable_type: described_class.name, auditable_id: record.id, action: 'destroy')).not_to exist
  end

  it 'removes this account metadata through the native account lifecycle without changing a different account' do
    owned = described_class.create!(attributes)
    other = create(:account)
    other_user = create(:user, account: other)
    other_team = create(:team, account: other)
    other_member = other.account_users.find_by!(user: other_user)
    preserved = described_class.create!(account: other, team: other_team, account_user: other_member, kind: 'additional')
    account.destroy!
    expect(described_class.exists?(owned.id)).to be(false)
    expect(described_class.find(preserved.id).kind).to eq('additional')
    expect(Account.exists?(other.id)).to be(true)
  end
end

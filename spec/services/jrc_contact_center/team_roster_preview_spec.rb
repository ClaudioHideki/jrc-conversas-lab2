require 'rails_helper'

RSpec.describe JrcContactCenter::TeamRosterPreview do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:manager) { account.account_users.find_by!(user: actor) }
  let(:operator) { create(:user, :contact_center_eligible, account: account) }
  let(:member) { account.account_users.find_by!(user: operator) }
  let(:team) { create(:team, account: account) }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC preview issuer', relationship_type: 'internal') }
  let(:business) { account.jrc_crm_business_units.create!(operating_company: company, code: 'PREVIEW', name: 'SYNTHETIC business') }
  let(:unit) do
    JrcContactCenter::Unit.create!(account: account, code: 'PREVIEW', name: 'SYNTHETIC operational unit', kind: 'sac',
                                   settings: { issuer_company_id: company.id, business_unit_id: business.id })
  end
  let(:queue) { JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'PREVIEW', name: 'SYNTHETIC preview queue') }
  let!(:membership) { JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member) }
  let(:preview) { described_class.new(account: account, actor: manager, team: team, user_ids: [operator.id], operation: 'destroy') }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'GROUP', structure_managed: true)
    member.update!(custom_role: create(:custom_role, account: account, permissions: []))
    team.add_members([operator.id])
    account.jrc_crm_team_scopes.create!(team: team, scope: 'GROUP')
    account.jrc_crm_user_business_units.create!(user: operator, team: team, scope: 'GROUP', structure_managed: true)
    JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: %w[jrc_contact_center_view jrc_contact_center_operate])
  end

  it 'reports the real configured queue impact while leaving all native records and caches unchanged' do
    original = team.team_members.sole.id
    expect(team).not_to receive(:add_members)
    expect(team).not_to receive(:remove_members)
    expect(Audited.audit_class).not_to receive(:create!)
    impact = preview.call.sole
    expect(impact).to include(queue: queue, before_ids: [member.id], after_ids: [])
    expect(team.team_members.reload.pluck(:id)).to eq([original])
    expect(membership.reload).to be_active
  end

  it 'detects lost functional permission even if independent corporate coverage remains' do
    account.jrc_crm_user_business_units.create!(user: operator, scope: 'GROUP', structure_managed: true)
    expect(preview.call.sole.fetch(:queue)).to eq(queue)
  end

  it 'detects lost corporate coverage even if the native profile still permits operation' do
    member.update!(custom_role: nil)
    expect(preview.call.sole.fetch(:queue)).to eq(queue)
  end

  it 'preserves independent corporate and functional sources instead of demanding an unnecessary review' do
    member.update!(custom_role: nil)
    account.jrc_crm_user_business_units.create!(user: operator, scope: 'GROUP', structure_managed: true)
    expect(preview.call).to be_empty
  end

  it 'preserves a second valid team that independently supplies both authorities' do
    another = create(:team, account: account)
    another.add_members([operator.id])
    account.jrc_crm_team_scopes.create!(team: another, scope: 'GROUP')
    account.jrc_crm_user_business_units.create!(user: operator, team: another, scope: 'GROUP', structure_managed: true)
    JrcContactCenter::AccessGrant.create!(account: account, team: another, allowed: %w[jrc_contact_center_view jrc_contact_center_operate])
    expect(preview.call).to be_empty
  end

  it 'does not confuse an offline provider-pending operator with an unconfigured agent' do
    expect(JrcContactCenter::AgentStateSnapshot.new(account_user: member).call.fetch(:eligible)).to be(false)
    expect(preview.call.sole.fetch(:before_ids)).to eq([member.id])
  end

  it 'does not turn an explicit individual denial into team eligibility' do
    JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member).update!(denied: ['jrc_contact_center_operate'])
    expect(preview.call).to be_empty
  end

  it 'does not infer individual eligibility from inherited functional grants' do
    JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member).update!(eligible: false)
    expect(preview.call).to be_empty
  end

  it 'does not count an operator whose native authentication has been disabled' do
    operator.update!(confirmed_at: nil)
    expect(preview.call).to be_empty
    expect(team.members).to include(operator)
  end

  it 'does not count an inactive or supervisor-only membership as configured replacement' do
    other = create(:user, :contact_center_eligible, account: account)
    account.jrc_crm_user_business_units.create!(user: other, scope: 'GROUP', structure_managed: true)
    peer = account.account_users.find_by!(user: other)
    JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: peer, role: 'supervisor')
    expect(preview.call.sole.fetch(:after_ids)).to be_empty
  end

  it 'uses fresh eligibility on each preview rather than retaining a previous permission result' do
    expect(preview.call.sole.fetch(:queue)).to eq(queue)
    JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member).update!(eligible: false)
    expect(preview.call).to be_empty
  end

  it 'keeps legacy native removal available when Call Center is explicitly disabled' do
    account.disable_features!('jrc_contact_center')
    expect(preview.call).to be_empty
  end

  it 'does not require a last-agent review for an inactive queue' do
    queue.update!(status: 'inactive')
    expect(preview.call).to be_empty
  end

  %i[starts_at ends_at].each do |field|
    it "does not count a configured membership outside its #{field} window" do
      membership.update!(field => field == :starts_at ? 1.hour.from_now : 1.hour.ago)
      expect(preview.call).to be_empty
    end
  end

  it 'requires coverage of every impacted queue rather than returning a partial authorized list' do
    other_business = account.jrc_crm_business_units.create!(operating_company: company, code: 'OTHER', name: 'SYNTHETIC other business')
    other_unit = JrcContactCenter::Unit.create!(account: account, code: 'OTHER', name: 'SYNTHETIC other unit', kind: 'sac',
                                                settings: { issuer_company_id: company.id, business_unit_id: other_business.id })
    other_queue = JrcContactCenter::Queue.create!(account: account, unit: other_unit, code: 'OTHER', name: 'SYNTHETIC other queue')
    JrcContactCenter::QueueMembership.create!(account: account, queue: other_queue, account_user: member)
    expect(preview.call.map { |row| row.fetch(:queue).id }).to contain_exactly(queue.id, other_queue.id)
    account.jrc_crm_user_business_units.find_by!(user: actor).update!(scope: 'BUSINESS_UNIT', company: company, business_unit: business)
    expect { preview.call }.to raise_error(Pundit::NotAuthorizedError)
    expect(team.members).to include(operator)
  end

  it 'does not disclose an impacted queue to a manager outside its current corporate scope' do
    account.jrc_crm_user_business_units.find_by!(user: actor).update!(active: false)
    expect { preview.call }.to raise_error(Pundit::NotAuthorizedError)
    expect(team.members).to include(operator)
  end

  it 'requires native configuration permission before returning last-agent impact details' do
    JrcContactCenter::AccessGrant.find_by!(account: account, account_user: manager).update!(denied: ['jrc_contact_center_configure'])
    expect { preview.call }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'requires native team-management permission even if the actor can configure Call Center' do
    manager.update!(role: :agent)
    expect { preview.call }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'treats canonical string-ID no-op replacement as no withdrawal' do
    comparison = described_class.new(account: account, actor: manager, team: team, user_ids: [operator.id.to_s], operation: 'update')
    expect(comparison.call).to be_empty
    expect(comparison.before_ids).to eq(comparison.after_ids)
  end

  it 'refuses a foreign user before computing the proposed membership set' do
    foreign = create(:user, account: create(:account))
    expect do
      described_class.new(account: account, actor: manager, team: team, user_ids: [foreign.id], operation: 'update')
    end.to raise_error(ActiveRecord::RecordNotFound)
  end
end

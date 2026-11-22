require 'rails_helper'

RSpec.describe JrcContactCenter::PauseApprovalCoverage do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:companies) do
    %w[A B].map { |code| account.master_companies.create!(name: "SYNTHETIC pause issuer #{code}", relationship_type: 'internal') }
  end
  let(:businesses) do
    companies.map { |company| account.jrc_crm_business_units.create!(operating_company: company, code: "U#{company.id}", name: company.name) }
  end
  let(:units) do
    businesses.map do |business|
      JrcContactCenter::Unit.create!(account: account, code: business.code, name: business.name, kind: 'sac',
                                     settings: { issuer_company_id: business.company_id, business_unit_id: business.id })
    end
  end
  let(:queues) do
    units.map do |unit|
      JrcContactCenter::Queue.create!(account: account, unit: unit, code: "coverage-#{unit.id}", name: unit.name,
                                      service_kind: 'voice', strategy: 'provider', status: 'active')
    end
  end
  let(:reader) { described_class.new(context: { account: account, account_user: member, user: actor }) }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs', 'jrc_approvals')
    member.update!(custom_role: create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_operate]))
    businesses.each do |business|
      account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company_id: business.company_id,
                                                  business_unit: business, active: true, structure_managed: true)
    end
    queues.each do |queue|
      JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member, role: 'agent', active: true)
    end
  end

  it 'captures every affected unit and corporate scope rather than selecting just the operating queue' do
    result = reader.call
    expect(result.fetch('all_affected_units')).to be(true)
    expect(result.fetch('units').pluck('id')).to eq(units.map { |unit| unit.id.to_s })
    expect(result.fetch('groups').pluck('issuer_company_id')).to eq(companies.map { |company| company.id.to_s })
    expect(result.fetch('groups').flat_map { |row| row.fetch('unit_ids') }).to eq(units.map { |unit| unit.id.to_s })
    expect(result.fetch('actor_user_id')).to eq(actor.id.to_s)
    expect(result).to include('local_only' => true, 'provider_confirmed' => false)
    expect(result.fetch('digest')).to match(/\A[0-9a-f]{64}\z/)
  end

  it 'deduplicates units while preserving the actual memberships of multiple queues' do
    unit = units.first
    extra = JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'extra-coverage', name: 'SYNTHETIC extra queue',
                                            service_kind: 'voice', strategy: 'provider', status: 'active')
    JrcContactCenter::QueueMembership.create!(account: account, queue: extra, account_user: member, role: 'agent', active: true)
    result = reader.call
    expect(result.fetch('units').size).to eq(2)
    expect(result.fetch('memberships').size).to eq(3)
    expect(result.fetch('groups').first.fetch('unit_ids')).to eq([unit.id.to_s])
  end

  it 'keeps a stable read-only digest without creating state, requests, approvals, grants or audit events' do
    models = [JrcContactCenter::AgentStateEvent, JrcContactCenter::DeferredPauseRequest,
              JrcApprovals::Request, JrcCrm::UserBusinessUnit, Audited::Audit]
    before = models.map(&:count)
    first = reader.call
    second = reader.call
    expect(second).to eq(first)
    expect(models.map(&:count)).to eq(before)
    expect(first.fetch('memberships').pluck('queue_id')).to eq(queues.map { |queue| queue.id.to_s })
  end

  it 'refreshes corporate coverage and does not mutate or silently extend a captured prior impact' do
    original = reader.call
    account.jrc_crm_user_business_units.find_by!(user: actor, business_unit: businesses.last).update!(active: false)
    current = reader.call
    expect(current.fetch('units').pluck('id')).to eq([units.first.id.to_s])
    expect(current.fetch('digest')).not_to eq(original.fetch('digest'))
    expect(original.fetch('units').size).to eq(2)
    expect(original.fetch('groups').flat_map { |row| row.fetch('unit_ids') }.size).to eq(2)
  end

  it 'rejects permission revocation on a reused instance rather than reconstructing authority from the member ID' do
    reader.call
    member.custom_role.update!(permissions: %w[jrc_contact_center_view])
    expect { reader.call }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'does not impersonate a different member of the same account through a chosen member context' do
    other = create(:user, :contact_center_eligible, account: account, role: :agent)
    chosen = described_class.new(context: { account: account, account_user: member, user: other })
    expect { chosen.call }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rejects a member belonging to another account without returning its operational units' do
    other = create(:account)
    user = create(:user, :contact_center_eligible, account: other, role: :agent)
    chosen = described_class.new(context: { account: account, account_user: other.account_users.find_by!(user: user), user: actor })
    expect { chosen.call }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'fails closed when an affected operational unit lacks an explicit native corporate mapping' do
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'GROUP', active: true, structure_managed: true)
    unit = JrcContactCenter::Unit.create!(account: account, code: 'unmapped', name: 'SYNTHETIC unmapped', kind: 'sac')
    queue = JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'unmapped', name: unit.name,
                                            service_kind: 'voice', strategy: 'provider', status: 'active')
    JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member, role: 'agent', active: true)
    expect { reader.call }.to raise_error(JrcContactCenter::OperationError, 'pause_approval_scope_missing')
  end

  it 'revalidates explicit Call Center eligibility before every capture' do
    reader.call
    JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member).update!(eligible: false)
    expect { reader.call }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'revalidates the account feature without applying any pause or enabling it again' do
    reader.call
    account.disable_features!('jrc_contact_center')
    expect { reader.call }.to raise_error(Pundit::NotAuthorizedError)
    expect(account.reload.feature_enabled?('jrc_contact_center')).to be(false)
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
  end
end

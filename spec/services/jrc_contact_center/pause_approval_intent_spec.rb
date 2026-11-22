require 'rails_helper'

RSpec.describe JrcContactCenter::PauseApprovalIntent do
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

  let(:catalog) { JrcContactCenter::PauseCatalog.new(account: account) }
  let(:definition) do
    { 'code' => 'synthetic_reviewed', 'name' => 'SYNTHETIC reviewed pause', 'category' => 'SYNTHETIC', 'description' => '', 'active' => true,
      'minimum_minutes' => 1, 'default_minutes' => 5, 'maximum_minutes' => 10, 'unit_ids' => [], 'custom_role_ids' => [],
      'approval_required' => true }
  end
  let(:attributes) do
    { command_id: SecureRandom.uuid, expected_state_version: '0', reason_code: definition.fetch('code'),
      expected_request_revision: JrcContactCenter::DeferredPauseRevision.token(account: account, member: member) }
  end

  before do
    Current.user = actor
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs', 'jrc_approvals')
    permissions = %w[jrc_contact_center_view jrc_contact_center_operate jrc_approvals_request_create]
    member.update!(custom_role: create(:custom_role, account: account, permissions: permissions))
    businesses.each do |business|
      account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company_id: business.company_id,
                                                  business_unit: business, active: true, structure_managed: true)
    end
    queues.each do |queue|
      JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member, role: 'agent', active: true)
    end
    catalog.update!({ 'enforced' => true, 'entries' => [definition] }, expected_revision: catalog.revision, activation_confirmed: true)
  end

  after { Current.reset }

  it 'captures an authenticated immutable-input intent covering every affected corporate scope' do
    result = reader.call(attributes)
    payload = result.fetch('payload')
    expect(result.fetch('required')).to be(true)
    expect(payload.fetch('coverage').fetch('groups').size).to eq(2)
    expect(payload.fetch('coverage').fetch('units').pluck('id')).to eq(units.map { |unit| unit.id.to_s })
    expect(payload.fetch('intent')).to include('reason_code' => definition.fetch('code'), 'justification' => '')
    expect(result.fetch('digest')).to eq(JrcApprovals::Ledger.digest(payload))
    expect(result).to include('local_only' => true, 'provider_confirmed' => false)
  end

  it 'never narrows global pause approval to the selected operating queue' do
    result = reader.call(attributes.merge(queue_id: queues.first.id.to_s))
    expect(result.fetch('payload').fetch('intent').fetch('queue_id')).to eq(queues.first.id.to_s)
    expect(result.fetch('payload').fetch('coverage').fetch('groups').size).to eq(2)
    expect(result.fetch('payload').fetch('coverage').fetch('memberships').size).to eq(2)
  end

  it 'creates no operational state, pending intent, approval, policy, grant or audit during preview' do
    models = [JrcContactCenter::AgentStateEvent, JrcContactCenter::DeferredPauseRequest,
              JrcApprovals::Request, JrcApprovals::Policy, JrcCrm::UserBusinessUnit, Audited::Audit]
    previous = models.map(&:count)
    result = reader.call(attributes)
    expect(result.fetch('required')).to be(true)
    expect(models.map(&:count)).to eq(previous)
  end

  it 'does not activate a stored catalogue merely because a reason has an approval flag' do
    catalog.update!({ 'enforced' => false, 'entries' => [definition] }, expected_revision: catalog.revision)
    account.disable_features!('jrc_approvals')
    expect(reader.call(attributes).fetch('required')).to be(false)
    expect(account.reload.feature_enabled?('jrc_approvals')).to be(false)
    expect(catalog.call.fetch('enforced')).to be(false)
  end

  it 'preserves a canonical old reason with no new approval field' do
    legacy = definition.except('approval_required')
    catalog.update!({ 'enforced' => true, 'entries' => [legacy] }, expected_revision: catalog.revision)
    expect(reader.call(attributes).fetch('required')).to be(false)
    expect(catalog.call.fetch('entries').sole).to eq(legacy)
    expect(catalog.call.fetch('entries').sole).not_to have_key('approval_required')
  end

  it 'treats an explicit false flag as legacy rather than converting it into a mandatory approval' do
    disabled = definition.merge('approval_required' => false)
    catalog.update!({ 'enforced' => true, 'entries' => [disabled] }, expected_revision: catalog.revision)
    expect(reader.call(attributes).fetch('required')).to be(false)
    expect(catalog.call.fetch('entries').sole.fetch('approval_required')).to be(false)
  end

  it 'requires native request-create authority independently of Call Center operate' do
    member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_operate])
    expect { reader.call(attributes) }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcApprovals::Request.where(account: account)).to be_empty
  end

  it 'fails closed if Central is disabled instead of falling back to an unapproved pause' do
    account.disable_features!('jrc_approvals')
    expect { reader.call(attributes) }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
  end

  it 'does not impersonate an operator by accepting their member ID with another authenticated user' do
    other = create(:user, :contact_center_eligible, account: account, role: :agent)
    chosen = described_class.new(context: { account: account, account_user: member, user: other })
    expect { chosen.call(attributes) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'does not accept an operational queue owned by another account' do
    other = create(:account)
    unit = JrcContactCenter::Unit.create!(account: other, code: 'foreign', name: 'SYNTHETIC foreign', kind: 'sac')
    queue = JrcContactCenter::Queue.create!(account: other, unit: unit, code: 'foreign', name: unit.name)
    expect { reader.call(attributes.merge(queue_id: queue.id.to_s)) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'invalidates the impact digest after actual membership revocation without editing a prior capture' do
    values = attributes
    first = reader.call(values)
    JrcContactCenter::QueueMembership.find_by!(account: account, account_user: member, queue: queues.last).update!(active: false)
    current = reader.call(values)
    expect(current.fetch('digest')).not_to eq(first.fetch('digest'))
    expect(current.fetch('payload').fetch('coverage').fetch('groups').size).to eq(1)
    expect(first.fetch('payload').fetch('coverage').fetch('groups').size).to eq(2)
  end

  it 'rejects client supplied impact units instead of treating them as a scope grant' do
    expect { reader.call(attributes.merge(unit_ids: [units.first.id])) }.to raise_error(JrcContactCenter::OperationError, 'invalid_deferred_pause')
    expect(JrcContactCenter::DeferredPauseRequest.where(account: account)).to be_empty
  end

  it 'binds the review to its native request identity without putting mutable call-state versions into the approval digest' do
    values = attributes
    first = reader.call(values)
    next_state = reader.call(values.merge(expected_state_version: '123'))
    another = reader.call(values.merge(command_id: SecureRandom.uuid))
    expect(next_state.fetch('digest')).to eq(first.fetch('digest'))
    expect(another.fetch('digest')).not_to eq(first.fetch('digest'))
    expect(first.fetch('payload').fetch('request_id')).to eq(values.fetch(:command_id))
    expect(JrcContactCenter::DeferredPauseInput::FIELDS).to eq(
      %i[command_id expected_state_version expected_request_revision reason_code queue_id justification]
    )
  end
end

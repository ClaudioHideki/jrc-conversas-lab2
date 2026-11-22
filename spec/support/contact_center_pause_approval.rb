# Explicit synthetic fixtures only. No installed policy, grant, real actor, provider command or commercial assumption.
RSpec.shared_context 'with all-scope native pause approval' do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:companies) do
    %w[A B].map { |code| account.master_companies.create!(name: "SYNTHETIC pause issuer #{code}", relationship_type: 'internal') }
  end
  let(:businesses) do
    companies.map { |company| account.jrc_crm_business_units.create!(operating_company: company, code: "P#{company.id}", name: company.name) }
  end
  let(:units) do
    businesses.map do |business|
      JrcContactCenter::Unit.create!(account: account, code: business.code, name: business.name, kind: 'sac',
                                     settings: { issuer_company_id: business.company_id, business_unit_id: business.id })
    end
  end
  let(:queues) do
    units.map do |unit|
      JrcContactCenter::Queue.create!(account: account, unit: unit, code: "pause-#{unit.id}", name: unit.name,
                                      service_kind: 'voice', strategy: 'provider', status: 'active')
    end
  end
  let(:catalog) { JrcContactCenter::PauseCatalog.new(account: account) }
  let(:definition) do
    { 'code' => 'synthetic_reviewed', 'name' => 'SYNTHETIC reviewed pause', 'category' => 'SYNTHETIC', 'description' => '', 'active' => true,
      'minimum_minutes' => 1, 'default_minutes' => 5, 'maximum_minutes' => 10, 'unit_ids' => [], 'custom_role_ids' => [],
      'approval_required' => true }
  end
  let(:manager) { JrcContactCenter::DeferredPauseManager.new(account: account, member: member) }
  let(:values) do
    { command_id: SecureRandom.uuid, expected_state_version: JrcContactCenter::AgentStateSnapshot.new(account_user: member).version,
      expected_request_revision: JrcContactCenter::DeferredPauseRevision.token(account: account, member: member),
      reason_code: definition.fetch('code') }
  end
  let(:policy_author) do
    user = create(:user, account: account, role: :agent)
    entry = account.account_users.find_by!(user: user)
    entry.update!(custom_role: create(:custom_role, account: account, permissions: %w[jrc_approvals_policy_manage]))
    account.jrc_crm_user_business_units.create!(user: user, scope: 'GROUP', active: true, structure_managed: true)
    entry
  end
  let(:reviewers) do
    businesses.map do |business|
      user = create(:user, :contact_center_eligible, account: account, role: :agent)
      entry = account.account_users.find_by!(user: user)
      permissions = %w[jrc_contact_center_view jrc_contact_center_approve jrc_approvals_decide jrc_approvals_view_audit]
      entry.update!(custom_role: create(:custom_role, account: account, permissions: permissions))
      account.jrc_crm_user_business_units.create!(user: user, scope: 'BUSINESS_UNIT', company_id: business.company_id,
                                                  business_unit: business, active: true, structure_managed: true)
      entry
    end
  end

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs', 'jrc_approvals')
    Current.user = actor
    permissions = %w[jrc_contact_center_view jrc_contact_center_operate jrc_approvals_request_create]
    member.update!(custom_role: create(:custom_role, account: account, permissions: permissions))
    businesses.each do |business|
      account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company_id: business.company_id,
                                                  business_unit: business, active: true, structure_managed: true)
    end
    queues.each { |queue| JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member, role: 'agent') }
    catalog.update!({ 'enforced' => true, 'entries' => [definition] }, expected_revision: catalog.revision, activation_confirmed: true)
  end

  after { Current.reset }

  def pause_context
    { account: account, account_user: member, user: actor }
  end

  def publish_pause_policy(index)
    business = businesses.fetch(index)
    service = JrcApprovals::Policies.new(account: account, user: policy_author.user)
    row = service.create!(code: "SYNTHETIC_PAUSE_#{business.id}", name: 'SYNTHETIC pause approval', module_key: 'contact_center', event_key: 'pause',
                          issuer_company_id: business.company_id, business_unit_id: business.id,
                          definition: approval_definition([reviewers.fetch(index)]))
    service.validate!(policy_id: row.id, expected_version: row.lock_version)
    service.publish!(policy_id: row.id, expected_version: row.reload.lock_version)
  end

  def publish_all_pause_policies
    businesses.each_index.map { |index| publish_pause_policy(index) }
  end

  def create_reviewed_pause
    preview = JrcContactCenter::PauseApprovalIntent.new(context: pause_context).call(values)
    manager.request_reviewed!(values, expected_approval_digest: preview.fetch('digest'))
  end

  def pause_requests
    JrcApprovals::Request.where(account: account, module_key: 'contact_center', event_key: 'pause').order(:id).to_a
  end

  def approve_pause_requests
    pause_requests.each do |request|
      index = businesses.index { |business| business.id == request.business_unit_id }
      approval_vote({ account: account }, reviewers.fetch(index), request)
    end
  end

  def apply_pause(row)
    manager.apply!(request_id: row.request_id, expected_state_version: JrcContactCenter::AgentStateSnapshot.new(account_user: member).version)
  end
end

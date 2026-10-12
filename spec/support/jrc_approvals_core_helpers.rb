module JrcApprovalsCoreHelpers
  def approval_scope(account: create(:account), amount: 2000)
    account.enable_features!('jrc_approvals')
    company = JrcCustomers::Company.create!(account: account, name: 'Synthetic internal issuer', relationship_type: 'internal')
    unit = JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: 'Synthetic unit', code: SecureRandom.hex(4),
      settings: { test_amount: amount, test_currency: 'BRL', test_quantity: '2.50', test_deadline: '2026-12-31T18:00:00-03:00' })
    { account: account, company: company, unit: unit }
  end

  def approval_actor(scope, permissions: JrcApprovals::Authorization::PERMISSIONS, role: :agent)
    user = create(:user, account: scope[:account], role: role)
    member = scope[:account].account_users.find_by!(user: user)
    custom_role = create(:custom_role, account: scope[:account], permissions: permissions)
    member.update!(custom_role: custom_role)
    JrcCrm::UserBusinessUnit.create!(account: scope[:account], user: user, company: scope[:company], business_unit: scope[:unit],
      scope: 'BUSINESS_UNIT', structure_managed: true, active: true)
    member
  end

  def approval_definition(members, mode: 'any', quorum: 1, selection: 'exclusive', priority: 10)
    { 'schema_version' => 1, 'condition' => { 'const' => true }, 'selection' => { 'mode' => selection, 'priority' => priority },
      'execution' => 'sequential', 'completion' => 'all_steps', 'expires_in_seconds' => 3600,
      'allow_self_approval' => false, 'delegation_allowed' => false, 'reopen_mode' => 'disabled',
      'steps' => [{ 'code' => 'review', 'mode' => mode, 'quorum' => quorum,
        'assignees' => members.map { |member| { 'type' => 'account_user', 'id' => member.id } },
        'authority' => { 'const' => true }, 'actions' => %w[approved rejected returned escalated], 'on_reject' => 'rejected' }] }
  end

  def approval_publish(scope, author, definition, code: SecureRandom.hex(6))
    manager = JrcApprovals::Policies.new(account: scope[:account], user: author.user)
    policy = manager.create!(code: code, name: 'Synthetic policy', module_key: 'synthetic', event_key: 'review',
      issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id, definition: definition)
    manager.validate!(policy_id: policy.id, expected_version: policy.lock_version)
    manager.publish!(policy_id: policy.id, expected_version: policy.reload.lock_version)
  end

  def approval_request(scope, requester, key: SecureRandom.hex(6))
    JrcApprovals::Requests.new(account: scope[:account], user: requester.user)
      .create!(key: 'synthetic.review', resource_id: scope[:unit].id, idempotency_key: key).first
  end

  def approval_vote(scope, actor, request, **overrides)
    JrcApprovals::Decisions.new(account: scope[:account], user: actor.user).call(**{
      request_id: request.id, step_code: 'review', decision: 'approved', reason: 'Explicit synthetic evidence',
      expected_version: request.reload.lock_version, idempotency_key: SecureRandom.hex(6)
    }.merge(overrides))
  end
end

# This read-only contract exists only in tests. It reads persisted native units, never request payload values.
RSpec.configure do |config|
  config.include JrcApprovalsCoreHelpers, approval_core: true
  config.before(:suite) do
    JrcApprovals::Catalog.register(key: 'synthetic.review', version: 1, model: JrcCrm::BusinessUnit,
      fields: { 'amount' => 'money', 'quantity' => 'decimal', 'code' => 'string', 'active' => 'boolean',
                'count' => 'integer', 'deadline' => 'datetime' },
      authorize: lambda { |user, unit|
        JrcApprovals::Authorization.new(account: unit.account, user: user).covered?(unit.company_id, unit.id)
      },
      capture: lambda { |unit|
        { issuer_company_id: unit.company_id, business_unit_id: unit.id,
          values: { amount: { amount_cents: unit.settings.fetch('test_amount'), currency: unit.settings.fetch('test_currency') },
                    quantity: unit.settings.fetch('test_quantity'), code: unit.code, active: unit.active,
                    count: unit.id, deadline: unit.settings.fetch('test_deadline') } }
      }) if config.files_to_run.any? { |path| path.include?('jrc_approvals') }
  end
  config.after(:suite) do
    JrcApprovals::Catalog.instance_variable_get(:@mutex).synchronize do
      JrcApprovals::Catalog.instance_variable_get(:@entries).delete('synthetic.review')
    end
  end
end

# Explicit synthetic data for isolated native/browser acceptance only.
module JrcApprovalBrowserFixture
  def self.member(account, company, unit, nonce, name, password, permissions)
    user = User.create!(name: "Synthetic #{name}", email: "#{name}-#{nonce}@example.test", password: password,
                        password_confirmation: password, confirmed_at: Time.current, ui_settings: { locale: 'pt_BR' })
    role = CustomRole.create!(account: account, name: "Synthetic approval #{name}", permissions: permissions) if permissions
    membership = AccountUser.create!(account: account, user: user, role: :agent, custom_role: role)
    if permissions
      JrcCrm::UserBusinessUnit.create!(account: account, user: user, company: company, business_unit: unit,
                                      scope: 'BUSINESS_UNIT', structure_managed: true, active: true)
    end
    membership
  end

  def self.proposal(account, unit, owner, product, contact, name)
    record = JrcCrm::Proposal.create!(account: account, contact: contact, owner: owner.user,
                                     business_unit: unit, title: name)
    record.proposal_items.create!(product: product, name_snapshot: product.name, unit_price_cents: 1000,
                                  quantity: 1, discount_cents: 200, billing_model: 'one_time', unit_name: 'unidade')
    record.reload
  end

  def self.policy(account, unit, author, principals, nonce, name)
    definition = {
      'schema_version' => 1, 'condition' => { 'const' => true },
      'selection' => { 'mode' => 'exclusive', 'priority' => 10 }, 'execution' => 'sequential',
      'completion' => 'all_steps', 'expires_in_seconds' => 3600, 'allow_self_approval' => false,
      'delegation_allowed' => true, 'reopen_mode' => 'disabled',
      'adjustments' => { 'schema_version' => 1, 'fields' => { 'discount_cents' => { 'min' => 0, 'max' => 500 } } },
      'steps' => [{ 'code' => 'review', 'mode' => 'any', 'quorum' => 1,
                    'assignees' => principals.map { |member| { 'type' => 'account_user', 'id' => member.id } },
                    'authority' => { 'const' => true }, 'actions' => %w[approved rejected returned escalated], 'on_reject' => 'rejected' }]
    }
    manager = JrcApprovals::Policies.new(account: account, user: author.user)
    record = manager.create!(code: "layout-#{nonce}", name: name, module_key: 'crm', event_key: 'proposal_send',
                             issuer_company_id: unit.company_id, business_unit_id: unit.id, definition: definition)
    manager.validate!(policy_id: record.id, expected_version: record.lock_version)
    manager.publish!(policy_id: record.id, expected_version: record.reload.lock_version)
    record
  end

  def self.build!(nonce:, product_sha:, output:)
    raise 'Synthetic nonce missing' unless nonce.match?(/\A[0-9a-f]{32}\z/)
    raise 'Synthetic fixture already exists' if Account.exists?(name: "Approval browser #{nonce}")
    account = Account.create!(name: "Approval browser #{nonce}", locale: 'pt_BR')
    account.enable_features!('jrc_approvals', 'jrc_crm')
    company = JrcCustomers::Company.create!(account: account, name: 'Synthetic issuer for layout validation', relationship_type: 'internal')
    unit = JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: 'Authorized synthetic unit', code: nonce.first(12))
    password = "Synthetic-#{SecureRandom.hex(16)}!9"
    full = JrcApprovals::Authorization::PERMISSIONS + ['jrc_crm']
    people = {}
    %w[requester reviewer recipient delegate denied].each do |name|
      permissions = name == 'denied' ? nil : full
      people[name] = member(account, company, unit, nonce, name, password, permissions)
    end
    requester, reviewer, recipient = people.values_at('requester', 'reviewer', 'recipient')
    rule = policy(account, unit, requester, [reviewer, recipient], nonce, 'Synthetic commercial approval — Word layout')
    contact = Contact.create!(account: account, name: 'Synthetic customer, no external channels')
    product = JrcCrm::Product.create!(account: account, name: 'Synthetic product', sku: nonce, unit_price_cents: 1000,
                                     minimum_price_cents: 900, maximum_discount_percent: 100, discount_approval_percent: 100,
                                     billing_model: 'one_time', sales_unit: 'unidade')
    origins = 29.times.map { |index| proposal(account, unit, requester, product, contact, "Synthetic approval layout #{index}") }
    requests = origins.each_with_index.map do |record, index|
      JrcApprovals::CommercialGate.new(account: account, user: requester.user)
        .request!(key: 'crm.proposal_send', resource_id: record.id, idempotency_key: "#{nonce}-#{index}").first.id
    end
    simulation = proposal(account, unit, reviewer, product, contact, 'Synthetic simulation owned source')
    other_company = JrcCustomers::Company.create!(account: account, name: 'Synthetic confidential issuer', relationship_type: 'internal')
    other_unit = JrcCrm::BusinessUnit.create!(account: account, operating_company: other_company, name: 'Denied synthetic unit', code: "#{nonce.first(10)}-2")
    JrcCrm::UserBusinessUnit.create!(account: account, user: requester.user, company: other_company, business_unit: other_unit,
                                    scope: 'BUSINESS_UNIT', structure_managed: true, active: true)
    other_actor = member(account, other_company, other_unit, nonce, 'other-unit', password, full)
    policy(account, other_unit, requester, [other_actor], "#{nonce}-other", 'CONFIDENTIAL_OTHER_UNIT')
    other_origin = proposal(account, other_unit, requester, product, contact, 'CONFIDENTIAL_OTHER_UNIT_SOURCE')
    other_request = JrcApprovals::CommercialGate.new(account: account, user: requester.user)
      .request!(key: 'crm.proposal_send', resource_id: other_origin.id, idempotency_key: "#{nonce}-other").first
    foreign_account = Account.create!(name: "Foreign approval browser #{nonce}", locale: 'pt_BR')
    foreign_account.enable_features!('jrc_approvals', 'jrc_crm')
    credentials = { account_id: account.id, email: reviewer.user.email, password: password, policy_id: rule.id,
                    request_ids: requests, source_ids: origins.map(&:id), simulation_resource_id: simulation.id,
                    other_unit_request_id: other_request.id, other_unit_id: other_unit.id, foreign_account_id: foreign_account.id,
                    users: people.transform_values { |member| { id: member.id, email: member.user.email, password: password } },
                    product_sha: product_sha }
    File.write(output, JSON.generate(credentials))
    File.chmod(0o600, output)
    puts JSON.generate(passed: true, fixture: 'isolated_native_commercial', requests: requests.length,
                       covered_units: 1, denied_units: 1, foreign_accounts: 1, external_operations: false)
  end
end

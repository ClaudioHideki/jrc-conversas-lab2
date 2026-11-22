# Isolated fixture only. No grants, commercial settings or policies may be inferred for real accounts.
class JrcContactCenter::SyntheticPauseApprovalSeed
  def self.call(account:, admin:, operator:, queues:)
    config = ApplicationRecord.connection_db_config
    owned = [ENV['GITHUB_ACTIONS'] == 'true', ENV['RUNNER_ENVIRONMENT'] == 'github-hosted', Rails.env.test?,
             config.database == 'jrc_sd_bc_portal_concurrency_20261025_test', config.configuration_hash[:host] == '127.0.0.1',
             ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15', account.name.start_with?('SYNTHETIC pause '), account.name.end_with?('-approval')].all?
    raise 'Exclusive synthetic pause approval fixture required' unless owned

    new(account, admin, operator, queues).call
  end
  private_class_method :new

  def initialize(account, admin, operator, queues)
    @account = account
    @admin = admin
    @operator = operator
    @queues = queues
  end

  def call
    prepare_actors
    extra = extra_unit
    units = [@queues.first.unit, extra]
    reviewers = units.map { |unit| reviewer(unit) }
    units.each_with_index { |unit, index| publish_policy(unit, reviewers.fetch(index)) }
    configure_reason
    session_payload(units, reviewers)
  end

  private

  def prepare_actors
    @account.enable_features!('jrc_approvals')
    @admin.custom_role.update!(permissions: @admin.custom_role.permissions | ['jrc_approvals_policy_manage'])
    @operator.custom_role.update!(permissions: @operator.custom_role.permissions | ['jrc_approvals_request_create'])
  end

  def session_payload(units, reviewers)
    { affected_unit_ids: units.map(&:id), affected_unit_names: units.map(&:name),
      approval_reviewers: reviewers.zip(units).map do |member, unit|
        { account_user_id: member.id, user_id: member.user_id, unit_id: unit.id,
          business_unit_id: unit.settings.fetch('business_unit_id'), auth: member.user.create_new_auth_token }
      end }
  end

  def extra_unit
    company = @account.master_companies.create!(name: 'SYNTHETIC approval issuer C', relationship_type: 'internal', active: true)
    business = @account.jrc_crm_business_units.create!(operating_company: company, code: 'APPROVAL-C', name: 'SYNTHETIC approval business C')
    unit = JrcContactCenter::Unit.create!(account: @account, code: business.code, name: 'SYNTHETIC approval unit C', kind: 'sac',
                                          settings: { issuer_company_id: company.id, business_unit_id: business.id })
    @account.jrc_crm_user_business_units.create!(user: @operator.user, company: company, business_unit: business,
                                                 scope: 'BUSINESS_UNIT', structure_managed: true, active: true)
    queue = JrcContactCenter::Queue.create!(account: @account, unit: unit, code: unit.code, name: 'SYNTHETIC approval queue C')
    JrcContactCenter::QueueMembership.create!(account: @account, queue: queue, account_user: @operator, role: 'agent', active: true)
    unit
  end

  def reviewer(unit)
    user = User.new(name: "SYNTHETIC scoped pause reviewer #{unit.code}", email: "cc-pause-review-#{SecureRandom.hex(8)}@example.test",
                    password: JrcContactCenter::SyntheticPassword.generate, confirmed_at: Time.current)
    user.skip_confirmation_notification!
    user.save!
    permissions = %w[jrc_contact_center_view jrc_contact_center_approve jrc_approvals_decide jrc_approvals_view_audit]
    role = CustomRole.create!(account: @account, name: "SYNTHETIC pause reviewer #{unit.code}", permissions: permissions)
    member = AccountUser.create!(account: @account, user: user, role: :agent, custom_role: role)
    JrcContactCenter::AccessGrant.create!(account: @account, account_user: member, eligible: true)
    @account.jrc_crm_user_business_units.create!(user: user, company_id: unit.settings.fetch('issuer_company_id'),
                                                 business_unit_id: unit.settings.fetch('business_unit_id'), scope: 'BUSINESS_UNIT',
                                                 structure_managed: true, active: true)
    member
  end

  def publish_policy(unit, member)
    service = JrcApprovals::Policies.new(account: @account, user: @admin.user)
    policy = service.create!(code: "SYNTHETIC_PAUSE_#{unit.id}", name: "SYNTHETIC pause policy #{unit.code}",
                             module_key: 'contact_center', event_key: 'pause', issuer_company_id: unit.settings.fetch('issuer_company_id'),
                             business_unit_id: unit.settings.fetch('business_unit_id'), definition: definition(member))
    service.validate!(policy_id: policy.id, expected_version: policy.lock_version)
    service.publish!(policy_id: policy.id, expected_version: policy.reload.lock_version)
  end

  def definition(member)
    { 'schema_version' => 1, 'condition' => { 'const' => true }, 'selection' => { 'mode' => 'exclusive', 'priority' => 10 },
      'execution' => 'sequential', 'completion' => 'all_steps', 'expires_in_seconds' => 3600,
      'allow_self_approval' => false, 'delegation_allowed' => false, 'reopen_mode' => 'disabled',
      'steps' => [{ 'code' => 'gestor', 'mode' => 'any', 'quorum' => 1,
                    'assignees' => [{ 'type' => 'account_user', 'id' => member.id }], 'authority' => { 'const' => true },
                    'actions' => %w[approved rejected returned escalated], 'on_reject' => 'rejected' }] }
  end

  def configure_reason
    catalog = JrcContactCenter::PauseCatalog.new(account: @account)
    entry = { 'code' => 'approval_break', 'name' => 'SYNTHETIC pausa com aprovação', 'category' => 'SYNTHETIC',
              'description' => '', 'active' => true, 'minimum_minutes' => 1, 'default_minutes' => 5, 'maximum_minutes' => 10,
              'unit_ids' => [], 'custom_role_ids' => [], 'justification_required' => true, 'approval_required' => true }
    catalog.update!({ 'enforced' => true, 'entries' => [entry] }, expected_revision: catalog.revision, activation_confirmed: true)
  end
end

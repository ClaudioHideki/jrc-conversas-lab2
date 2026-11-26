# frozen_string_literal: true

# Prepared after the existing public Project scenario, in its same four nonce-owned accounts.
# CRM deliberately reuses an explicitly unit-mapped native Lead; it never invents the unit of a new Lead.
require_relative '../spec/integration/jrc_contact_center/owned_public_ending_queue'

class JrcContactCenter::SyntheticMixedEndingSeed
  MARKER = 'jrc_cc_owned_mixed_ending'
  CODE = 'SYNTHETIC_MIXED_CRM_SD'
  RIGHTS = %w[jrc_crm jrc_service_desk_module_view jrc_service_desk_tickets_view jrc_service_desk_tickets_create
              jrc_service_desk_lookups_view jrc_service_desk_customers_view].freeze

  def self.call(account:)
    new(account).call
  end

  def initialize(account)
    @account = account
  end

  def call
    verify_owned_completed_project!
    prepare_members!
    JrcServiceDesk::NativeExecutionContext.with(account: @account, account_user: @admin, user: @admin.user) do
      native_destination!
      configure_rule!
      prepare_attendance!
      persist_owned_marker!
    end
  end

  private

  def verify_owned_completed_project!
    configuration = SyntheticPublicEndingQueue.configuration!
    raise 'Owned mixed fixture account required' unless configuration.fetch('account_ids').include?(@account.id)
    raise 'Do not overwrite a prepared mixed fixture' if @account.custom_attributes.key?(MARKER)

    @previous = JrcContactCenter::EndingActionOrigin.where(account: @account).sole
    verify_completed_project_results!
    @operator = @account.account_users.find(@previous.actor_account_user_id)
    @queue = JrcContactCenter::Queue.where(account: @account).find(@previous.queue_id)
  end

  def verify_completed_project_results!
    attempts = JrcContactCenter::EndingDestinationAttempt.where(account: @account, origin: @previous).includes(:outcome)
    qualification = JrcContactCenter::Qualification.where(account: @account).find(@previous.source_qualification_id)
    valid = attempts.count == 3 && attempts.count { |row| row.outcome&.outcome == 'succeeded' } == 2
    valid &&= JrcProjects::Task.where(account: @account).count == 2 && qualification.completed_at.present?
    raise 'Complete and preserve the native Project browser scenario first' unless valid
  end

  def prepare_members!
    @corporate_scope_sha = Digest::SHA256.hexdigest(JSON.generate(corporate_scope))
    @admin = administrator_member
    @account.enable_features!('jrc_crm', 'jrc_customer_master', 'jrc_service_desk')
    [@admin, @operator].each do |member|
      member.update!(crm_enabled: true)
      member.custom_role.update!(permissions: (member.custom_role.permissions + RIGHTS).uniq)
    end
    policy = JrcContactCenter::ModulePolicy.new({ account: @account, account_user: @operator, user: @operator.user }, :contact_center)
    raise 'Original operator must not gain configuration authority' unless @operator.agent? && !policy.configure?
  end

  def administrator_member
    @account.account_users.where(role: :administrator).includes(:user).select do |row|
      row.user.name.start_with?('SYNTHETIC ') && row.user.name.end_with?(' administrator')
    end.sole
  end

  def corporate_scope
    @account.jrc_crm_user_business_units.where(user: @operator.user).order(:id)
            .pluck(:scope, :company_id, :business_unit_id, :active, :structure_managed, :team_id)
  end

  def native_destination!
    company = JrcServiceDesk::OperatorCompany.create!(account: @account, code: 'SYNTHETIC-MIXED', name: 'SYNTHETIC mixed SD issuer', active: true)
    @unit = JrcServiceDesk::Unit.create!(account: @account, operator_company: company, code: 'SYNTHETIC-MIXED',
                                         name: 'SYNTHETIC mixed Service Desk', active: true)
    [@admin, @operator].each do |member|
      JrcServiceDesk::UnitMembership.create!(account: @account, unit: @unit, account_user: member, active: true)
    end
    @status = JrcServiceDesk::TicketStatus.create!(account: @account, unit: @unit, code: 'SYNTHETIC-MIXED-OPEN',
                                                   name: 'SYNTHETIC mixed initial status', active: true, phase: 'open', initial: true, position: 0)
    @priority = JrcServiceDesk::Priority.create!(account: @account, unit: @unit, code: 'SYNTHETIC-MIXED',
                                                 name: 'SYNTHETIC mixed priority', active: true, position: 1)
    @scope = JrcContactCenter::EndingActionQueueScope.where(account: @account, source_queue_id: @queue.id).order(revision: :desc).first!
    business = @account.jrc_crm_business_units.find(@scope.business_unit_id)
    business.update!(settings: business.settings.merge('service_desk_unit_id' => @unit.id.to_s))
    @scope = JrcContactCenter::EndingActionQueueScope.where(account: @account, source_queue_id: @queue.id).order(revision: :desc).first!
  end

  def configure_rule!
    previous = @previous.version.definition.fetch('entries').find { |row| row['code'] == 'SYNTHETIC_PUBLIC_MANUAL' }
    raise 'Existing explicit reason required' unless previous

    @reason = previous.fetch('reason_code')
    input = previous.deep_dup.merge('code' => CODE, 'name' => CODE, 'scope_revision' => @scope.integrity_sha256,
                                    'destination_schema_version' => 2, 'execution_mode' => 'automatic', 'active' => true,
                                    'actions' => [{ 'kind' => 'crm', 'parameters' => {} }, service_desk_action])
    input.delete('scope')
    @account.reload
    revision = JrcContactCenter::AcwPolicy.new(account: @account).revision
    JrcContactCenter::EndingActions::ConfigureRule.new(account: @account, member: @admin, input: input, expected_revision: revision).call
    @account.reload
    revision = JrcContactCenter::AcwPolicy.new(account: @account).revision
    JrcContactCenter::EndingActions::ActivateRule.new(account: @account, member: @admin, rule_code: CODE,
                                                      request_key: SecureRandom.uuid, expected_revision: revision).call
  end

  def service_desk_action
    attributes = { 'title' => 'SYNTHETIC mixed native Ticket', 'description' => 'SYNTHETIC mixed reviewed description',
                   'status_id' => @status.id.to_s, 'priority_id' => @priority.id.to_s }
    { 'kind' => 'service_desk',
      'parameters' => { 'unit_id' => @unit.id.to_s, 'service_id' => nil, 'attributes' => attributes } }
  end

  def prepare_attendance!
    @contact = @account.contacts.create!(name: 'SYNTHETIC mixed authorized contact')
    @lead = @account.jrc_crm_leads.create!(owner: @operator.user, contact: @contact, business_unit_id: @scope.business_unit_id,
                                           name: 'SYNTHETIC existing scoped Lead')
    call = JrcContactCenter::CallSession.create!(account: @account, provider: 'synthetic', correlation_id: SecureRandom.uuid,
                                                 direction: 'inbound', status: 'connected', started_at: Time.current, answered_at: Time.current,
                                                 current_unit: @queue.unit, current_queue: @queue, contact: @contact)
    JrcContactCenter::CallLeg.create!(account: @account, call_session: call, account_user: @operator, queue: @queue,
                                      direction: 'inbound', status: 'connected', started_at: call.started_at, answered_at: call.answered_at)
    call.update!(status: 'ended', ended_at: Time.current)
    @qualification = JrcContactCenter::Qualification.find_by!(account: @account, account_user: @operator, call_session: call)
    @origin = JrcContactCenter::EndingActionOrigin.find_by!(account: @account, source_qualification_id: @qualification.id)
    raise 'No action before explicit classification' if JrcContactCenter::EndingDestinationAttempt.exists?(account: @account, origin: @origin)
  end

  def persist_owned_marker!
    current_scope = Digest::SHA256.hexdigest(JSON.generate(corporate_scope))
    raise 'Preserve the original unit scope; never grant GROUP for the witness' unless current_scope == @corporate_scope_sha

    # Real transaction failure only after native Ticket creation; never replace its service with a fake success/failure.
    name = "cc_public_mixed_sd_#{Integer(@account.id)}"
    check = "account_id <> #{Integer(@account.id)} OR destination_kind <> 'service_desk'"
    ApplicationRecord.connection.add_check_constraint(:jrc_contact_center_ending_destination_executions, check, name: name)
    marker = { 'source_sha' => ENV.fetch('GITHUB_SHA'), 'qualification_id' => @qualification.id,
               'call_session_id' => @qualification.call_session_id, 'origin_id' => @origin.id,
               'lead_id' => @lead.id, 'lead_before' => Digest::SHA256.hexdigest(JSON.generate(@lead.attributes)),
               'source_qualification_id' => @previous.source_qualification_id, 'constraint' => name, 'reason_code' => @reason,
               'corporate_scope_before_sha256' => @corporate_scope_sha }
    @account.reload
    @account.update!(custom_attributes: @account.custom_attributes.merge(MARKER => marker))
    marker.slice('qualification_id', 'call_session_id', 'origin_id', 'lead_id', 'reason_code').merge(
      'rule_code' => CODE, 'CRM_reuses_existing_unit_mapped_Lead' => true
    )
  end
end

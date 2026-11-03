require 'rails_helper'

RSpec.describe 'NICO acceptance of the snapshots behind native SLA clocks' do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures

  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'Native clock customer') }
  let(:ticket) { sd_ticket(company_id: company.id) }
  let(:context) { JrcNico::Helpdesk::Context.new(sd_account_user) }
  let(:access) { context.access }
  let(:clock) do
    lc_snapshot(ticket)
    lc_publish(definition: lc_definition(tracked: true))
    lc_execute(ticket, 'work_status')
    ticket.reload.sla_cycles.order(number: :desc).first.sla_clocks.find_by!(kind: 'resolution')
  end
  let(:policy) do
    definition = JrcNico::Helpdesk::Definition.defaults.merge('unit_ids' => [sd_unit.id], 'company_ids' => [company.id],
      'operator_ids' => [sd_account_user.id])
    JrcNico::Helpdesk::PolicyVersion.create!(account: sd_account, author: sd_account_user, number: 1, state: 'draft', enabled: false,
      definition: definition, digest: JrcNico::Helpdesk::Definition.digest(definition))
  end

  before do
    sd_account.update!(custom_attributes: { 'nico_enabled' => true })
    sd_account.enable_features!('jrc_relationship', 'jrc_customer_master', 'jrc_crm')
  end

  def pending_snapshot(snapshot = clock.sla_cycle.sla_snapshot)
    batch = JrcMigrations::Batch.create!(account: sd_account, created_by: sd_user, source: 'nico_clock',
      domain: 'service_desk_sla_snapshots', source_digest: 'a' * 64)
    JrcMigrations::Mapping.create!(account: sd_account, batch: batch, source: 'nico_clock', domain: 'service_desk_sla_snapshots',
      legacy_id: snapshot.id.to_s, target_id: snapshot.id, source_digest: 'a' * 64, target_digest: 'b' * 64, source_updated_at: Time.current)
  end

  def add_current_cycle
    clock
    snapshot = create(:jrc_sd_snapshot, ticket: ticket, version: 2)
    ticket.sla_cycles.create!(account: sd_account, unit: sd_unit, lifecycle_policy_version: ticket.lifecycle_policy_version,
      sla_snapshot: snapshot, number: 2, started_at: Time.current)
  end

  it 'gates a pending cycle snapshot before constructing the native clock projection' do
    pending_snapshot
    expect(JrcServiceDesk::ClockProjection).not_to receive(:new)
    result = JrcNico::DomainActions.new(access).call('read_service_ticket', { 'ticket_id' => ticket.id })
    expect(result.dig(:record, 'sla')).to be_nil
  end

  it 'omits helpdesk clock facts before interpreting the pending calendar' do
    pending_snapshot
    expect(JrcServiceDesk::LifecycleClocks).not_to receive(:verify_snapshot!)
    facts = JrcNico::Helpdesk::Facts.new(context: context, policy: policy, ticket: ticket, trigger: 'timer').call
    expect(facts.keys & %w[clock_id due_at sla_elapsed_seconds]).to be_empty
  end

  it 'reauthorizes a saved event clock against its actual source snapshot' do
    pending_snapshot
    expect do
      JrcNico::Helpdesk::EvidenceAccess.new(context, ticket, { 'clock_id' => clock.id }).call
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'rejects a report clock from an older pending cycle even if the current cycle is native' do
    add_current_cycle
    pending_snapshot
    payload = { 'ticket_ids' => [ticket.id], 'kpis' => { 'metrics' => [{ 'evidence' => { 'clock_ids' => [clock.id] } }] } }
    expect do
      JrcNico::Helpdesk::ReportResources.new(context, payload).call
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'keeps a current native SLA projection available when an unused older snapshot is pending' do
    add_current_cycle
    pending_snapshot
    result = JrcNico::DomainActions.new(access).call('read_service_ticket', { 'ticket_id' => ticket.id })
    expect(result.dig(:record, 'sla')).to be_present
    result[:resources].each { |type, id| JrcNico::DomainAccess.authorize_resource!(access, type, id) }
  end

  it 'treats a completed clock from a pending snapshot as unknown closure evidence' do
    clock
    lc_execute(ticket, 'resolve')
    close = lc_execute(ticket, 'close')
    reader = JrcNico::Helpdesk::KpiClosureEvidence.new(context)
    expect(reader.overdue(close, { 'basis' => 'calendar' })).not_to be_nil
    pending_snapshot
    expect(reader.overdue(close, { 'basis' => 'calendar' })).to be_nil
  end

  it 'does not include an unaccepted clock in the prealert cohort or evidence manifest' do
    clock.update!(due_at: 1.hour.ago)
    reader = JrcNico::Helpdesk::Kpis.new(member: sd_account_user, policy: policy, from: 1.day.ago, until_at: Time.current)
    before = reader.call[:metrics].find { |row| row[:key] == 'K4' }
    expect(before[:denominator]).to eq(1)
    pending_snapshot
    after = reader.call[:metrics].find { |row| row[:key] == 'K4' }
    expect(after.dig(:evidence, 'clock_ids')).not_to include(clock.id)
    expect(after[:denominator]).to eq(0)
    expect(after[:value]).to be_nil
  end

  it 'restores saved clock evidence after acceptance and still enforces the separate SLA grant' do
    mapping = pending_snapshot
    reader = JrcNico::Helpdesk::EvidenceAccess.new(context, ticket, { 'clock_id' => clock.id })
    expect { reader.call }.to raise_error(ActiveRecord::RecordNotFound)
    mapping.update!(accepted_at: Time.current)
    expect(reader.call).to be(true)

    result = JrcNico::DomainActions.new(access).call('read_service_ticket', { 'ticket_id' => ticket.id })
    resources = result[:resources].reject { |type, _| type == 'JrcServiceDesk::Ticket' }
    role = create(:custom_role, account: sd_account, permissions: %w[jrc_service_desk_module_view jrc_service_desk_tickets_view])
    sd_account_user.update!(custom_role_id: role.id)
    expect do
      resources.each { |type, id| JrcNico::DomainAccess.authorize_resource!(access, type, id) }
    end.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'does not use operational SLA evidence to authorize raw contract snapshot reads' do
    clock
    role = create(:custom_role, account: sd_account,
      permissions: %w[jrc_service_desk_module_view jrc_service_desk_tickets_view jrc_service_desk_sla_view])
    sd_account_user.update!(custom_role_id: role.id)
    fresh = JrcNico::Helpdesk::Context.new(sd_account_user)
    result = JrcNico::DomainActions.new(fresh.access).call('read_service_ticket', { 'ticket_id' => ticket.id })
    expect(result.dig(:record, 'sla')).to be_present
    result[:resources].each { |type, id| JrcNico::DomainAccess.authorize_resource!(fresh.access, type, id) }
    expect(JrcServiceDesk::SlaSnapshotPolicy.new(fresh.native.to_h, clock.sla_cycle.sla_snapshot).show?).to be(false)
  end

  it 'rejects persisted operational SLA references when read through another tenant' do
    clock
    result = JrcNico::DomainActions.new(access).call('read_service_ticket', { 'ticket_id' => ticket.id })
    other = create(:account, custom_attributes: { 'nico_enabled' => true })
    other_actor = create(:user, account: other, role: :administrator)
    other_access = JrcNico::OperationalAccess.new(account: other, user: other_actor).authorize!
    resources = result[:resources].select { |type, _| type.start_with?('JrcNico::OperationalSla') }
    expect(resources).not_to be_empty
    resources.each do |type, id|
      expect { JrcNico::DomainAccess.authorize_resource!(other_access, type, id) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end

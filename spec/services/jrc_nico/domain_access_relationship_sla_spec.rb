require 'rails_helper'

RSpec.describe JrcNico::DomainAccess do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  around { |example| travel_to(Time.utc(2026, 11, 6, 18)) { example.run } }

  let(:access) { JrcNico::OperationalAccess.new(account: sd_account, user: sd_user) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: sd_account, owner: sd_user, contact: sd_contact) }
  let(:ticket) do
    row = sd_ticket(opened_at: Time.current)
    lc_snapshot(row)
    lc_execute(row, 'work_status')
    row
  end

  before do
    sd_as_admin!
    sd_account.update!(custom_attributes: sd_account.custom_attributes.merge('nico_enabled' => true))
    sd_account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    lc_publish(definition: lc_definition(tracked: true))
  end

  it 'reads actual clock evidence through the native tool and recognizes every clock receipt for current authorization without modifying clocks' do
    clocks = ticket.sla_cycles.sole.sla_clocks.order(:id)
    original = clocks.map(&:attributes)
    result = JrcNico::ToolExecutor.new(access).call('read_relationship_customer', 'assignment_id' => assignment.id)
    receipts = result.fetch(:resources).select { |row| row.first == 'JrcServiceDesk::SlaClock' }
    expect(receipts.map(&:last)).to match_array(clocks.pluck(:id))
    expect(JrcNico::DomainAccess::RESOURCE_TYPES).to include('JrcServiceDesk::SlaClock')
    receipts.each do |type, id|
      expect(described_class.authorize_resource!(access, type, id)).to eq(clocks.find(id))
    end
    expect(clocks.reload.map(&:attributes)).to eq(original)
  end

  it 'rejects a foreign account or lost native SLA access rather than granting access through a raw clock ID' do
    clock = ticket.sla_cycles.sole.sla_clocks.first!
    foreign = create(:user, account: sd_foreign_account, role: :administrator)
    sd_foreign_account.update!(custom_attributes: { 'nico_enabled' => true })
    sd_foreign_account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_service_desk')
    foreign_access = JrcNico::OperationalAccess.new(account: sd_foreign_account, user: foreign)
    expect do
      described_class.authorize_resource!(foreign_access, clock.class.name, clock.id)
    end.to raise_error(ActiveRecord::RecordNotFound)
    role = create(:custom_role, account: sd_account,
                                permissions: %w[contact_manage jrc_relationship_view jrc_service_desk_module_view
                                                jrc_service_desk_tickets_view jrc_service_desk_customers_view])
    sd_account_user.update!(role: :agent, custom_role: role)
    expect do
      described_class.authorize_resource!(access, clock.class.name, clock.id)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'clears saved answers on departmental SLA revocation while native ticket access and the general digest remain unchanged' do
    team = create(:team, account: sd_account)
    queue = create(:jrc_sd_queue, unit: sd_unit, team: team)
    row = sd_ticket(queue: queue, team: team, opened_at: Time.current)
    lc_snapshot(row)
    lc_execute(row, 'work_status')
    create(:team_member, team: team, user: sd_user)
    role = create(:custom_role, account: sd_account,
                                permissions: %w[contact_manage jrc_relationship_view jrc_relationship_manage jrc_relationship_team
                                                jrc_service_desk_module_view jrc_service_desk_tickets_view jrc_service_desk_customers_view
                                                jrc_service_desk_sla_view])
    sd_account_user.update!(role: :agent, custom_role: role)
    grant = { queue_id: queue.id, team_id: team.id, permissions: %w[tickets_view customers_view sla_view] }
    sd_membership.update!(restricted_supervision: true, supervision_grants: [grant])
    operator = JrcNico::OperatorSession.new(account: sd_account, user: sd_user)
    # Provider inference is simulated; the tool, persisted receipts, permissions and history checks are native.
    allow(JrcNico::OperationalInference).to receive(:call).and_return(
      { 'tool' => 'read_relationship_customer', 'arguments' => { 'assignment_id' => assignment.id } },
      { 'reply' => 'Synthetic authorized departmental SLA summary' }
    )
    command = operator.ask(message: 'Resumo autorizado do Relacionamento', request_id: SecureRandom.uuid)
    expect(command.reload.status).to eq('succeeded')
    expect(operator.session.reload.context.fetch('resources')).to include(['JrcServiceDesk::SlaClock', row.sla_cycles.sole.sla_clocks.first!.id])
    digest = JrcNico::OperatorContext.access_digest(operator.access)
    travel 1.second
    sd_membership.update!(supervision_grants: [grant.merge(permissions: %w[tickets_view customers_view])])
    current_access = JrcNico::OperationalAccess.new(account: sd_account, user: sd_user).authorize!
    expect(JrcNico::OperatorContext.access_digest(current_access)).to eq(digest)
    expect(described_class.new(current_access).ticket(row.id)).to eq(row)
    current = JrcNico::OperatorSession.new(account: sd_account, user: sd_user)
    expect(current.session.reload.messages).to eq([])
    expect(current.session.context).not_to have_key('resources')
    expect(command.reload.status).to eq('succeeded')
  end
end

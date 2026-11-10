require 'rails_helper'

RSpec.describe 'Calendar-aware scoped customer SLA signals', type: :request do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  around { |example| travel_to(Time.utc(2026, 11, 6, 18)) { example.run } }

  let(:headers) { sd_user.create_new_auth_token }
  let(:path) { "/api/v1/accounts/#{sd_account.id}/customers/contacts/#{sd_contact.id}/overview" }
  let(:assignment) { JrcRelationship::Assignment.create!(account: sd_account, contact: sd_contact, owner: sd_user) }
  let(:context) { JrcRelationship::Context.new(sd_account_user) }
  let(:ticket) do
    row = sd_ticket(opened_at: Time.current)
    lc_snapshot(row)
    lc_execute(row, 'work_status')
    row
  end
  let(:permissions_without_sla) do
    %w[contact_manage jrc_relationship_view jrc_relationship_manage jrc_relationship_team jrc_service_desk_module_view
       jrc_service_desk_tickets_view jrc_service_desk_customers_view]
  end
  let(:snapshot_attributes) do
    { account: sd_account, assignment: assignment, viewer: sd_user, score: 50, band: 'risk', factors: [], calculated_at: Time.current,
      config_scope_key: 'account', config_version: 1, access_signature: context.access_signature }
  end

  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    lc_publish(definition: lc_definition(tracked: true))
  end

  it 'does not call a weekend boundary a breach and counts an affected ticket once even when both clocks later breach' do
    original = ticket.sla_cycles.sole.sla_clocks.order(:id).map(&:attributes)
    travel_to(Time.utc(2026, 11, 8, 18))
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('sla_breached' => 0, 'capabilities' => include('service_desk_sla' => true))
    travel_to(Time.utc(2026, 11, 10, 18))
    get path, headers: headers
    expect(response.parsed_body.fetch('sla_breached')).to eq(1)
    expect(ticket.sla_cycles.sole.sla_clocks.order(:id).map(&:attributes)).to eq(original)
  end

  it 'does not consume idle time on a paused resolution clock after a synthetic native first-response receipt' do
    ticket
    conversation = create(:conversation, account: sd_account, contact: sd_contact)
    create(:inbox_member, inbox: conversation.inbox, user: sd_user)
    JrcServiceDesk::LinkConversationService.new(user_context: sd_context).call(ticket_id: ticket.id, conversation_id: conversation.id)
    travel 1.hour
    message = create(:message, account: sd_account, conversation: conversation, sender: sd_user, message_type: :outgoing, private: false,
                               content: 'Synthetic native response evidence', status: :delivered, source_id: 'synthetic-sla-receipt')
    JrcServiceDesk::NativeResponseRecorder.new(message, evidence: JrcServiceDesk::NativeResponseRecorder.evidence(message)).call
    lc_execute(ticket, 'pause', reason_code: 'customer')
    clocks = ticket.sla_cycles.sole.sla_clocks.order(:id)
    original = clocks.map(&:attributes)
    expect(clocks.pluck(:state)).to contain_exactly('completed', 'paused')
    travel 7.days
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('sla_breached')).to eq(0)
    signals = JrcRelationship::Processor.new(context: context, assignment: assignment).call
    expect(signals.fetch(:sla_breached)).to eq(0)
    expect(assignment.actions.where(kind: 'ticket')).not_to exist
    expect(clocks.reload.map(&:attributes)).to eq(original)
  end

  it 'retains an already consumed breach when a native pause happens after the budget was exceeded' do
    ticket
    travel_to(Time.utc(2026, 11, 10, 18))
    lc_execute(ticket, 'pause', reason_code: 'customer')
    resolution = ticket.sla_cycles.sole.sla_clocks.find_by!(kind: 'resolution')
    expect(resolution.state).to eq('paused')
    expect(resolution.elapsed_seconds).to be > resolution.budget_seconds
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('sla_breached')).to eq(1)
  end

  it 'keeps missing SLA access unavailable in both the customer summary and the health factor rather than inventing zero' do
    ticket
    assignment
    role = create(:custom_role, account: sd_account, permissions: permissions_without_sla)
    sd_account_user.update!(role: :agent, custom_role: role)
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('sla_breached' => nil, 'capabilities' => include('service_desk' => true, 'service_desk_sla' => false))
    signals = JrcRelationship::CustomerSignals.new(context: context, assignment: assignment).call
    factor = signals.fetch(:health).fetch(:factors).find { |row| row[:factor] == 'service_desk' }
    expect(factor).to include(available: false, normalized: nil, raw: include(breached: nil))
    expect(signals.fetch(:_source_ids).fetch(:sla_clocks)).to be_empty
  end

  it 'reauthorizes captured zero and legacy numeric SLA evidence after revocation without rewriting immutable snapshots' do
    ticket
    captured = [
      { '_source_ids' => { 'sla_clocks' => ticket.sla_cycles.sole.sla_clocks.pluck(:id) },
        'capabilities' => { 'service_desk_sla' => true }, 'sla_breached' => 0 },
      { '_source_ids' => {}, 'sla_breached' => 0 },
      { '_source_ids' => {} }
    ].map { |signals| JrcRelationship::HealthSnapshot.create!(**snapshot_attributes, signals: signals, fingerprint: SecureRandom.hex(16)) }
    before = captured.map(&:attributes)
    rows = JrcRelationship::HealthSnapshot.where(id: captured.map(&:id))
    expect(JrcRelationship::SnapshotAccess.scope(context, rows).pluck(:id)).to match_array(captured.map(&:id))
    role = create(:custom_role, account: sd_account, permissions: permissions_without_sla)
    sd_account_user.update!(role: :agent, custom_role: role)
    expect(JrcRelationship::SnapshotAccess.scope(JrcRelationship::Context.new(sd_account_user), rows).pluck(:id)).to eq([captured.last.id])
    role.update!(permissions: permissions_without_sla + ['jrc_service_desk_sla_view'])
    expect(JrcRelationship::SnapshotAccess.scope(JrcRelationship::Context.new(sd_account_user), rows).pluck(:id)).to match_array(captured.map(&:id))
    expect(captured.map { |row| row.reload.attributes }).to eq(before)
  end

  it 'does not expose legacy numeric priority SLA evidence through a missing-manifest branch or hide unrelated manual work' do
    rows = [
      { 'sla' => { 'breached_count' => 0, 'normalized' => 0 } }, {}
    ].map do |factors|
      JrcRelationship::Action.create!(account: sd_account, assignment: assignment, owner: sd_user, kind: 'manual',
                                      reason: 'Synthetic scoped priority', source_key: SecureRandom.uuid, factors: factors, metadata: {})
    end
    role = create(:custom_role, account: sd_account, permissions: permissions_without_sla)
    sd_account_user.update!(role: :agent, custom_role: role)
    expect(JrcRelationship::Context.new(sd_account_user).records(JrcRelationship::Action).where(id: rows.map(&:id)).pluck(:id)).to eq([rows.last.id])
    expect(rows.first.reload.factors.dig('sla', 'breached_count')).to eq(0)
  end

  it 'intersects customer and SLA departmental grants instead of expanding them through creator or native team membership' do
    finance = create(:team, account: sd_account)
    support = create(:team, account: sd_account)
    queues = [finance, support].map { |team| create(:jrc_sd_queue, unit: sd_unit, team: team) }
    tickets = queues.zip([finance, support]).map do |queue, team|
      row = sd_ticket(queue: queue, team: team, opened_at: Time.current)
      lc_snapshot(row)
      lc_execute(row, 'work_status')
      create(:team_member, team: team, user: sd_user)
      row
    end
    role = create(:custom_role, account: sd_account, permissions: permissions_without_sla + ['jrc_service_desk_sla_view'])
    sd_account_user.update!(role: :agent, custom_role: role)
    sd_membership.update!(restricted_supervision: true, supervision_grants: [
                            { queue_id: queues.first.id, team_id: finance.id, permissions: %w[tickets_view customers_view sla_view] },
                            { queue_id: queues.last.id, team_id: support.id, permissions: %w[tickets_view customers_view] }
                          ])
    travel_to(Time.utc(2026, 11, 10, 18))
    get path, headers: headers, params: { unit_id: sd_foreign_unit.id, user_id: sd_user.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('tickets_open' => 2, 'sla_breached' => 1)
    native = JrcCustomers::Visibility.new(account: sd_account, user: sd_user, account_user: sd_account_user)
    expect(native.sla_clocks.pluck(:ticket_id).uniq).to eq([tickets.first.id])
  end

  it 'does not authorize another account clock through an injected historical source ID' do
    ticket
    foreign = create(:account)
    foreign.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_service_desk')
    foreign_user = create(:user, account: foreign, role: :administrator)
    foreign_assignment = JrcRelationship::Assignment.create!(account: foreign, contact: create(:contact, account: foreign), owner: foreign_user)
    foreign_context = JrcRelationship::Context.new(foreign.account_users.find_by!(user: foreign_user))
    snapshot = JrcRelationship::HealthSnapshot.create!(account: foreign, assignment: foreign_assignment, viewer: foreign_user,
                                                       score: 50, band: 'risk', factors: [], calculated_at: Time.current,
                                                       config_scope_key: 'account', config_version: 1, fingerprint: SecureRandom.hex(16),
                                                       access_signature: foreign_context.access_signature,
                                                       signals: { '_source_ids' => { 'sla_clocks' => [ticket.sla_cycles.sole.sla_clocks.first.id] } })
    expect(JrcRelationship::SnapshotAccess.scope(foreign_context, JrcRelationship::HealthSnapshot.where(id: snapshot.id))).to be_empty
  end
end

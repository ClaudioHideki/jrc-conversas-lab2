# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Explicit departmental Service Desk supervision', type: :request do
  include_context 'JRC Service Desk domain'
  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:finance) { create(:team, account: sd_account, name: 'Synthetic finance') }
  let(:support) { create(:team, account: sd_account, name: 'Synthetic support') }
  let(:queue) { create(:jrc_sd_queue, unit: sd_unit, team: finance) }
  let(:other_queue) { create(:jrc_sd_queue, unit: sd_unit, team: support) }
  let(:permissions) do
    %w[tickets_view tickets_assign tickets_transfer notes_view notes_add history_view conversations_view sla_view customers_view
       dashboard_view reports_view reports_export]
  end
  let(:financial) { sd_ticket(queue: queue, team: finance, title: 'Authorized finance') }
  let(:outside) { sd_ticket(queue: other_queue, team: support, title: 'Restricted support') }

  before do
    create(:team_member, team: finance, user: sd_user)
    create(:team_member, team: support, user: sd_user)
    sd_membership.update!(restricted_supervision: true,
      supervision_grants: [{ 'queue_id' => queue.id, 'team_id' => finance.id, 'permissions' => permissions }])
  end

  it 'restricts lists, search, direct details, cockpit, history, notes and exports despite creator and native team membership' do
    financial
    outside
    get "#{base}/tickets", headers: headers
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([financial.id.to_s])
    get "#{base}/tickets", params: { q: outside.title }, headers: headers
    expect(response.parsed_body.dig('meta', 'total')).to eq(0)
    ['', '/cockpit', '/events', '/notes', '/timeline', '/export', '/customer_context'].each do |suffix|
      get "#{base}/tickets/#{outside.id}#{suffix}", headers: headers
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(outside.title)
    end
    get "#{base}/tickets/#{financial.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(sd_account_user.reload.role).to eq('agent')
    expect(JrcServiceDesk::OperationalContext.new(sd_context).capability?(:tickets_view_all)).to be(false)
  end

  it 'denies null, mismatched, foreign and legacy rows and keeps the boundary after grant revocation' do
    financial
    null_queue = sd_ticket(team: finance)
    null_team = sd_ticket(queue: queue, team: finance)
    null_team.update_columns(team_id: nil)
    mismatched = sd_ticket(queue: queue, team: finance)
    mismatched.update_columns(team_id: support.id)
    foreign = create(:jrc_sd_ticket, unit: sd_foreign_unit)
    other_unit = sd_ticket(unit: sd_other_unit, status: create(:jrc_sd_status, unit: sd_other_unit),
                          priority: create(:jrc_sd_priority, unit: sd_other_unit),
                          created_by_membership: create(:jrc_sd_membership, unit: sd_other_unit))
    [null_queue, null_team, mismatched, foreign, other_unit].each do |row|
      get "#{base}/tickets/#{row.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
    sd_membership.update!(supervision_grants: [])
    expect(JrcServiceDesk::TicketPolicy::Scope.new(sd_context, JrcServiceDesk::Ticket).resolve).to be_empty
    sd_membership.update_columns(supervision_grants: [{ queue_id: "#{queue.id}invalid", team_id: finance.id, permissions: permissions }])
    expect(JrcServiceDesk::TicketPolicy::Scope.new(sd_context, JrcServiceDesk::Ticket).resolve).to be_empty
  end

  it 'requires explicit read permissions on child APIs and does not infer history access from ticket visibility' do
    note = create(:jrc_sd_note, ticket: financial)
    event = create(:jrc_sd_event, ticket: financial)
    sd_membership.update!(supervision_grants: [{ queue_id: queue.id, team_id: finance.id, permissions: ['tickets_view'] }])
    expect(JrcServiceDesk::TicketPolicy.new(sd_context, financial).show?).to be(true)
    expect(JrcServiceDesk::TicketNotePolicy.new(sd_context, note).show?).to be(false)
    expect(JrcServiceDesk::TicketEventPolicy.new(sd_context, event).show?).to be(false)
    expect(JrcServiceDesk::TicketNotePolicy::Scope.new(sd_context, JrcServiceDesk::TicketNote).resolve).to be_empty
    expect(JrcCustomers::Visibility.new(**sd_context).ticket_events(JrcServiceDesk::Ticket.all)).to be_empty
    get "#{base}/tickets/#{financial.id}/notes/#{note.id}", headers: headers
    expect(response).to have_http_status(:forbidden)
    get "#{base}/operational_reports/export", params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:forbidden)
  end

  it 'limits dashboard, reports, CSV export and customer360 to the exact authorized tuple' do
    financial
    outside
    get "#{base}/dashboard", params: { unit_id: sd_unit.id }, headers: headers
    expect(response.parsed_body.dig('dashboard', 'total')).to eq(1)
    get "#{base}/operational_reports", params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([financial.id.to_s])
    get "#{base}/operational_reports/export", params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(financial.title)
    expect(response.body).not_to include(outside.title)
    expect(JrcCustomers::Visibility.new(**sd_context).tickets.pluck(:id)).to eq([financial.id])
  end

  it 'does not derive SLA, history, channel or customer metrics from a reports-only department grant' do
    financial
    inbox = create(:inbox, account: sd_account)
    create(:inbox_member, inbox: inbox, user: sd_user)
    conversation = create(:conversation, account: sd_account, inbox: inbox, contact: sd_contact, assignee: sd_user)
    create(:jrc_sd_conversation_link, ticket: financial, conversation: conversation)
    sd_membership.update!(supervision_grants: [{ queue_id: queue.id, team_id: finance.id,
      permissions: %w[tickets_view dashboard_view reports_view reports_export] }])

    query = JrcServiceDesk::OperationalReportQuery.new(user_context: sd_context, parameters: { unit_id: sd_unit.id })
    expect(query.relation.pluck(:id)).to eq([financial.id])
    %w[sla_view history_view conversations_view customers_view].each do |permission|
      expect(query.relation_for(permission)).to be_empty
    end
    expect(query.channels).to be_empty
    metrics = JrcServiceDesk::OperationalReportMetrics.new(query).call
    expect(metrics.dig(:reopen, :cohort_ticket_count)).to eq(0)
    expect(metrics.fetch(:sla).values.map { |value| value[:observed] }).to all(eq(0))
    dashboard = JrcServiceDesk::DashboardService.new(user_context: sd_context).call(parameters: { unit_id: sd_unit.id })
    expect(dashboard[:total]).to eq(1)
    expect(dashboard.dig(:supervision, :sla_coverage, :total_tickets)).to eq(0)
  end

  it 'authorizes manual assignment with automatic exclusion and rejects a transfer outside the department' do
    sd_account_user.update!(auto_assignment_enabled: false)
    post "#{base}/tickets/#{financial.id}/assign", params: {
      assignment: { assignee_account_user_id: sd_account_user.id }, expected_lock_version: financial.lock_version
    }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(financial.reload.assignee_membership_id).to eq(sd_membership.id)
    post "#{base}/tickets/#{financial.id}/transfer", params: {
      assignment: { queue_id: other_queue.id, team_id: support.id }, expected_lock_version: financial.lock_version
    }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(financial.reload.queue_id).to eq(queue.id)
  end

  it 'never includes a call from another conversation sharing the same contact' do
    skip 'Native enterprise calls unavailable' unless defined?(::Call)

    inbox = create(:inbox, account: sd_account)
    create(:inbox_member, inbox: inbox, user: sd_user)
    linked = create(:conversation, account: sd_account, inbox: inbox, contact: sd_contact, team: finance)
    unrelated = create(:conversation, account: sd_account, inbox: inbox, contact: sd_contact, team: support)
    create(:jrc_sd_conversation_link, ticket: financial, conversation: linked)
    create(:jrc_sd_conversation_link, ticket: outside, conversation: unrelated)
    allowed_call = create(:call, conversation: linked, accepted_by_agent: sd_user)
    create(:call, conversation: unrelated, accepted_by_agent: sd_user)
    sources = JrcServiceDesk::TimelineSources.new(ticket: financial,
      context: JrcServiceDesk::OperationalContext.new(sd_context)).call
    expect(sources.fetch('call').pluck(:id)).to eq([allowed_call.id])
    allowed_call.recording.attach(io: StringIO.new('Synthetic departmental recording'), filename: 'synthetic-department.wav',
                                  content_type: 'audio/wav')
    allowed_call.recording.blob.update!(metadata: { 'service_desk_scan_state' => 'clean' })
    attachment_path = "#{base}/tickets/#{financial.id}/timeline/call/#{allowed_call.id}/attachments/#{allowed_call.recording.id}"
    get attachment_path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq('Synthetic departmental recording')
    expect(response.headers['Location']).to be_nil
    sd_membership.update!(supervision_grants: [{ queue_id: queue.id, team_id: finance.id, permissions: ['tickets_view'] }])
    sources = JrcServiceDesk::TimelineSources.new(ticket: financial,
      context: JrcServiceDesk::OperationalContext.new(sd_context)).call
    expect(sources.fetch('call')).to be_empty
    get attachment_path, headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'rereads an exact operational assignee and its native automatic flag through the existing structural authority' do
    sd_as_admin!
    sd_account_user.update!(auto_assignment_enabled: false)
    get "#{base}/structure/members", params: { unit_id: sd_unit.id, account_user_id: sd_account_user.id }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('meta', 'total')).to eq(1)
    member = response.parsed_body.fetch('items').sole
    expect(member).to include('id' => sd_account_user.id.to_s, 'auto_assignment_enabled' => false)
    expect(member.dig('membership', 'id')).to eq(sd_membership.id.to_s)

    foreign = create(:account_user, account: sd_foreign_account)
    get "#{base}/structure/members", params: { unit_id: sd_unit.id, account_user_id: foreign.id }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to be_empty
  end
end

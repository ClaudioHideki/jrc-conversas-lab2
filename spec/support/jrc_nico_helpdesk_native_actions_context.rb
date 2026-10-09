# frozen_string_literal: true

# Synthetic native fixtures only; provider jobs are never performed by these examples.
RSpec.shared_context 'NICO HelpDesk native action chain' do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures

  let(:selected_rule) { 'R03' }
  let(:selected_group) { selected_rule == 'R03' ? 'E' : 'D2' }
  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'Synthetic native action customer') }
  let(:ticket) { sd_ticket(company_id: company.id) }
  let(:headers) { sd_user.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_nico/helpdesk" }
  let(:lead) do
    JrcCrm::Lead.create!(account: sd_account, owner: sd_user, contact: sd_contact, company: company, name: 'Explicit synthetic CRM source')
  end
  let(:definition) do
    value = JrcNico::Helpdesk::Definition.defaults.merge(
      'unit_ids' => [sd_unit.id], 'company_ids' => [company.id], 'operator_ids' => [sd_account_user.id]
    )
    value['rules'][selected_rule]['enabled'] = true
    value['rules'][selected_rule]['confirmed'] = true if value['rules'][selected_rule].key?('confirmed')
    value['groups'][selected_group]['enabled'] = true
    value
  end
  let(:policy) do
    JrcNico::Helpdesk::PolicyVersion.create!(
      account: sd_account, author: sd_account_user, number: 1, state: 'published', enabled: true,
      published_at: Time.current, definition: definition, digest: JrcNico::Helpdesk::Definition.digest(definition)
    )
  end
  let(:event) { native_action_event }
  let(:activity_input) { { 'activity' => { 'title' => 'Reviewed customer appointment', 'due_at' => 1.day.from_now.iso8601, 'lead_id' => lead.id } } }

  before do
    travel_to Time.iso8601('2026-10-08T12:00:00Z')
    sd_account.update!(custom_attributes: { 'nico_enabled' => true })
    sd_account.enable_features!('jrc_customer_master', 'jrc_crm')
    sd_as_admin!
  end

  after { travel_back }

  def native_action_event
    if selected_rule == 'R03'
      [ticket, *Array.new(4) { sd_ticket(company_id: company.id) }].each do |row|
        JrcNico::Helpdesk::TicketProfile.create!(account: sd_account, unit: sd_unit, ticket: row, company: company,
                                                 case_kind: 'defect', defect_key: 'voice.synthetic')
      end
    elsif selected_rule == 'R08'
      lc_publish(definition: lc_definition(tracked: true))
      lc_snapshot(ticket)
      lc_execute(ticket, 'work_status')
      clock = ticket.reload.sla_cycles.last.sla_clocks.find_by!(kind: 'resolution')
      travel_to(clock.due_at + 72.hours + 1, with_usec: true)
    else
      customer = selected_rule == 'R11' ? 'Notificação extrajudicial do advogado.' : 'Reclamação: novamente o mesmo problema.'
      note = JrcServiceDesk::AddNoteService.new(user_context: sd_context).call(
        ticket_id: ticket.id, attributes: { body: customer }, idempotency_key: SecureRandom.uuid
      )
      JrcNico::Helpdesk::ProfileWriter.new(sd_account_user).call(ticket_id: ticket.id, attributes: { customer_note_ids: [note.id] })
    end
    policy
    events = JrcNico::Helpdesk::Capture.new(sd_account_user).call(
      ticket: ticket.reload, trigger: 'monitor', origin_key: "native-actions:#{ticket.id}"
    )
    expect(events.pluck(:rule_key)).to eq([selected_rule])
    captured = events.fetch(0)
    expect(captured).to have_attributes(actor_id: sd_account_user.id, account_id: sd_account.id, policy_version_id: policy.id)
    JrcNico::Helpdesk::EventJob.perform_now(captured.id)
    expect(captured.reload).to have_attributes(state: 'prepared', reason: 'approval_required')
    captured
  end

  def action_preview(input)
    post "#{base}/group_preview", params: { event_id: event.id, group_key: selected_group, input: input }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    response.parsed_body
  end

  def prepare_native(input, tool)
    preview = action_preview(input)
    action = preview.fetch('actions').find { |row| row.fetch('tool') == tool }
    expect(action.fetch('can_prepare')).to be(true)
    post "#{base}/group_prepare", params: { event_id: event.id, group_key: selected_group, input: input,
                                            tool: tool, arguments: action.fetch('arguments'), preview_digest: preview.fetch('preview_digest') },
                                  headers: headers, as: :json
    expect(response).to have_http_status(:created)
    JrcNico::Helpdesk::Approval.find(response.parsed_body.fetch('id'))
  end

  def approve_native(approval)
    post "#{base}/approvals/#{approval.id}/approve", params: { payload_digest: approval.payload_digest }, headers: headers, as: :json
  end

  def approved_action(approval)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('state')).to eq('succeeded')
    expect(approval.reload.command.reload.status).to eq('succeeded')
    expect(approval.command.session).to have_attributes(account_id: sd_account.id, user_id: sd_user.id)
    approval.command
  end

  def verify_receipt_hidden(approval)
    get "#{base}/approvals", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('approvals').pluck('id')).not_to include(approval.id)
  end
end

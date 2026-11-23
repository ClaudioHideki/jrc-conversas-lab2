require 'rails_helper'

RSpec.describe 'Consolidated employee intake', type: :request do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  let(:team) { create(:team, account: sd_account) }
  let(:queue) { create(:jrc_sd_queue, unit: sd_unit, team: team, distribution_mode: 'manual') }
  let(:observer_user) { create(:user) }
  let(:observer_member) { create(:account_user, account: sd_account, user: observer_user, role: :agent) }
  let(:observer) { create(:jrc_sd_membership, unit: sd_unit, account_user: observer_member, manual_assignment_enabled: true) }
  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token.merge('Idempotency-Key' => 'synthetic-internal-intake') }
  let(:input) { { unit_id: sd_unit.id.to_s, internal_request: true, ticket: { title: 'Synthetic employee request', description: 'No real delivery' } } }

  before do
    sd_status
    sd_priority.update!(code: 'normal', name: 'Normal')
    sd_membership.update!(manual_assignment_enabled: true)
    observer
    create(:team_member, team: team, user: sd_user)
    create(:team_member, team: team, user: observer_user)
    sd_account.update!(internal_attributes: sd_account.internal_attributes.merge(
      JrcServiceDesk::InternalIntake::KEY => { sd_unit.id.to_s => {
        'queue_id' => queue.id.to_s, 'assignee_account_user_id' => sd_account_user.id.to_s,
        'observer_account_user_id' => observer.account_user_id.to_s
      } }
    ))
  end

  context 'with an automatically selected published SLA' do
    let(:service) do
      JrcServiceDesk::Service.create!(account: sd_account, unit: sd_unit, active: true, name: 'Synthetic internal service', code: 'internal')
    end
    let(:snapshot) do
      sd_snapshot_attributes.deep_stringify_keys.except('captured_at').merge(
        'policy_conditions' => { 'clock_budgets_seconds' => { 'first_response' => 3600, 'resolution' => 7200 } },
        'calendar_conditions' => { 'format' => JrcServiceDesk::SnapshotCalendar::VERSION,
          'weekly' => (1..7).to_h { |day| [day.to_s, [['00:00', '23:59']]] }, 'holidays' => [], 'exceptions' => {} })
    end

    before do
      lc_publish(definition: lc_definition(tracked: true))
      sd_as_admin!
      JrcServiceDesk::PublishOperationalRulesService.new(user_context: sd_context).call(
        unit_id: sd_unit.id, kind: 'sla_selection', enabled: true, expected_version: 0,
        definition: { 'rules' => [{ 'key' => 'published-intake', 'precedence' => 1,
          'match' => {}, 'output' => { 'snapshot' => snapshot } }] })
      sd_account_user.update!(role: :agent)
      values = sd_account.internal_attributes.deep_dup
      values[JrcServiceDesk::InternalIntake::KEY][sd_unit.id.to_s].merge!(
        'assignee_account_user_id' => observer.account_user_id.to_s, 'observer_account_user_id' => sd_account_user.id.to_s)
      sd_account.update!(internal_attributes: values)
      input[:service_id] = service.id.to_s
    end

    it 'creates the missing self contact and applies SLA without granting manual snapshot permissions, once on replay' do
      expect(JrcServiceDesk::OperationalContext.new(sd_context).capability?(:sla_snapshots_record)).to be(false)
      expect(sd_account.contacts.where(email: sd_user.email)).to be_empty
      2.times do
        post "#{base}/tickets", headers: headers, params: input, as: :json
        expect(response).to have_http_status(:created)
      end
      ticket = JrcServiceDesk::Ticket.find_by!(account: sd_account, idempotency_key: 'synthetic-internal-intake')
      expect(ticket.requester.email).to eq(sd_user.email)
      expect(sd_account.contacts.where(email: sd_user.email).count).to eq(1)
      expect(ticket.assignee_membership).to eq(observer)
      expect(ticket.sla_snapshots.count).to eq(1)
      expect(ticket.sla_cycles.count).to eq(1)
      expect(ticket.sla_cycles.sole.sla_clocks.count).to eq(2)
      expect(ticket.ticket_events.where(event_type: 'sla_snapshot_recorded').count).to eq(1)
      expect(ticket.ticket_events.where(event_type: 'operational_rule_applied').count).to eq(1)
      expect(sd_account_user.reload.role).to eq('agent')
      expect { JrcServiceDesk::RecordSlaSnapshotService.new(user_context: sd_context).call(
        ticket_id: ticket.id, attributes: snapshot.merge('captured_at' => ticket.opened_at.iso8601(6))) }.to raise_error(Pundit::NotAuthorizedError)
      post "#{base}/tickets/#{ticket.id}/sla_snapshots", headers: headers, as: :json,
        params: { snapshot: snapshot.merge('captured_at' => ticket.opened_at.iso8601(6)) }
      expect(response).to have_http_status(:forbidden)
      expect(ticket.sla_snapshots.count).to eq(1)
    end

    it 'applies the same published SLA to an explicit eligible recipient' do
      input[:ticket][:assignee_account_user_id] = sd_account_user.id.to_s
      post "#{base}/tickets", headers: headers, params: input, as: :json
      expect(response).to have_http_status(:created)
      ticket = JrcServiceDesk::Ticket.find(response.parsed_body.fetch('ticket_id'))
      expect(ticket.assignee_membership).to eq(sd_membership)
      expect(ticket.sla_snapshots.count).to eq(1)
      expect(ticket.sla_cycles.count).to eq(1)
    end

    it 'does not grant creation to a role lacking tickets_create even with a published SLA' do
      role = create(:custom_role, account: sd_account, permissions: %w[jrc_service_desk_module_view jrc_service_desk_tickets_view])
      sd_account_user.update!(custom_role_id: role.id)
      expect do
        post "#{base}/tickets", headers: headers, params: input, as: :json
        expect(response).to have_http_status(:not_found)
      end.not_to change(JrcServiceDesk::Ticket, :count)
      expect(sd_account.contacts.where(email: sd_user.email)).to be_empty
    end

    it 'does not apply published SLA across an unauthorized unit or a foreign account service' do
      expect do
        post "#{base}/tickets", headers: headers, params: input.merge(unit_id: sd_other_unit.id.to_s), as: :json
        expect(response).to have_http_status(:not_found)
        foreign_service = JrcServiceDesk::Service.create!(account: sd_foreign_account, unit: sd_foreign_unit,
          active: true, name: 'Synthetic foreign service', code: 'foreign')
        post "#{base}/tickets", headers: headers, params: input.merge(service_id: foreign_service.id.to_s), as: :json
        expect(response).to have_http_status(:not_found)
      end.not_to change(JrcServiceDesk::Ticket, :count)
      expect(sd_account.contacts.where(email: sd_user.email)).to be_empty
    end

    it 'keeps incompatible configured queue teams blocked before recording SLA' do
      TeamMember.where(team: team, user: observer_user).delete_all
      expect do
        post "#{base}/tickets", headers: headers, params: input, as: :json
        expect(response).to have_http_status(:not_found) # Required team membership is resolved with take!.
      end.not_to change(JrcServiceDesk::Ticket, :count)
      expect(sd_account.contacts.where(email: sd_user.email)).to be_empty
    end

    context 'when selecting a recipient in another team and queue' do
      let(:department) { create(:team, account: sd_account) }
      let(:department_queue) { create(:jrc_sd_queue, unit: sd_unit, team: department, distribution_mode: 'manual') }
      let(:recipient) do
        create(:jrc_sd_membership, unit: sd_unit, team: department, queue: department_queue, manual_assignment_enabled: true)
      end
      let(:chosen) { input.deep_merge(ticket: { assignee_account_user_id: recipient.account_user_id.to_s }) }

      before do
        create(:team_member, team: department, user: recipient.account_user.user)
      end

      it 'ignores an inactive service default queue and missing legacy configuration, preserving the exact recipient on replay' do
        service.update!(default_queue: queue)
        queue.update!(active: false)
        sd_account.update!(internal_attributes: sd_account.internal_attributes.except(JrcServiceDesk::InternalIntake::KEY))
        context = JrcServiceDesk::UiContextService.new(user_context: sd_context).call
        intake = context[:units].find { |row| row[:id] == sd_unit.id.to_s }.fetch(:internal_intake)
        expect(intake[:assignees].pluck(:id)).to include(recipient.account_user_id.to_s)
        expect(intake[:primary]).to be_nil
        expect(sd_account_user.reload.role).to eq('agent')
        expect(JrcServiceDesk::OperationalContext.new(sd_context).capability?(:sla_snapshots_record)).to be(false)
        ids = 2.times.map do
          post "#{base}/tickets", headers: headers, params: chosen, as: :json
          expect(response).to have_http_status(:created), response.body
          response.parsed_body.fetch('ticket_id')
        end
        expect(ids.uniq.size).to eq(1)
        ticket = JrcServiceDesk::Ticket.find(ids.first)
        expect(ticket).to have_attributes(assignee_membership_id: recipient.id, queue_id: department_queue.id, team_id: department.id)
        expect(ticket.requester.email).to eq(sd_user.email)
        expect(ticket.sla_snapshots.count).to eq(1)
        expect(ticket.sla_cycles.count).to eq(1)
        expect(JrcServiceDesk::Ticket.where(account: sd_account).count).to eq(1)
        get "#{base}/tickets/#{ticket.id}", headers: headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig('ticket', 'assignee', 'id')).to eq(recipient.account_user_id.to_s)
      end

      it 'does not replace the selected recipient with the disabled legacy or service default assignee' do
        service.update!(default_assignee_membership: observer, default_queue: queue)
        observer.update!(active: false, manual_assignment_enabled: false)
        post "#{base}/tickets", headers: headers, params: chosen, as: :json
        expect(response).to have_http_status(:created), response.body
        ticket = JrcServiceDesk::Ticket.find(response.parsed_body.fetch('ticket_id'))
        expect(ticket).to have_attributes(assignee_membership_id: recipient.id, queue_id: department_queue.id, team_id: department.id)
        expect(ticket.sla_snapshots.count).to eq(1)
      end

      it 'keeps the chosen recipient when the service default queue belongs to a different team' do
        service.update!(default_queue: queue)
        post "#{base}/tickets", headers: headers, params: chosen, as: :json
        expect(response).to have_http_status(:created), response.body
        ticket = JrcServiceDesk::Ticket.find(response.parsed_body.fetch('ticket_id'))
        expect(ticket).to have_attributes(assignee_membership_id: recipient.id, queue_id: department_queue.id, team_id: department.id)
      end

      it 'does not list or assign a recipient whose native authentication is inactive' do
        recipient.account_user.user.update!(confirmed_at: nil)
        expect(recipient.account_user.user.active_for_authentication?).to be(false)
        context = JrcServiceDesk::UiContextService.new(user_context: sd_context).call
        intake = context[:units].find { |row| row[:id] == sd_unit.id.to_s }.fetch(:internal_intake)
        expect(intake[:assignees].pluck(:id)).not_to include(recipient.account_user_id.to_s)
        expect do
          post "#{base}/tickets", headers: headers, params: chosen, as: :json
          expect(response).to have_http_status(:forbidden)
        end.not_to change(JrcServiceDesk::Ticket, :count)
      end

      it 'does not substitute a default when the selected operational membership is inactive' do
        recipient.update!(active: false)
        expect do
          post "#{base}/tickets", headers: headers, params: chosen, as: :json
          expect(response).to have_http_status(:not_found)
        end.not_to change(JrcServiceDesk::Ticket, :count)
      end

      it 'refuses an explicit recipient from another account without falling back to the local default' do
        foreign = create(:jrc_sd_membership, unit: sd_foreign_unit, manual_assignment_enabled: true)
        expect do
          post "#{base}/tickets", headers: headers,
            params: input.deep_merge(ticket: { assignee_account_user_id: foreign.account_user_id.to_s }), as: :json
          expect(response).to have_http_status(:not_found)
        end.not_to change(JrcServiceDesk::Ticket, :count)
      end
    end
  end

  it 'creates through the authenticated API with native employee identity and configured assignment' do
    post "#{base}/tickets", headers: headers, params: input, as: :json
    expect(response).to have_http_status(:created)
    ticket = JrcServiceDesk::Ticket.find_by!(account: sd_account, idempotency_key: 'synthetic-internal-intake')
    expect(ticket.reload).to have_attributes(unit_id: sd_unit.id, queue_id: queue.id, team_id: team.id,
      assignee_membership_id: sd_membership.id, status_id: sd_status.id, priority_id: sd_priority.id, service_id: nil)
    expect(ticket.requester).to have_attributes(account_id: sd_account.id, email: sd_user.email)
    expect(ticket.ticket_events.where(event_type: 'resource_updated').pluck(:data)).to include(
      include('internal_request' => true, 'observer_account_user_id' => observer.account_user_id))
    expect(JrcServiceDesk::UiContextService.new(user_context: sd_context).call[:units].find { |row| row[:id] == sd_unit.id.to_s })
      .to include(self_assignee: { id: sd_account_user.id.to_s, name: sd_user.name })
  end

  it 'replays the same API request without creating another ticket or another audit event' do
    post "#{base}/tickets", headers: headers, params: input, as: :json
    expect(response).to have_http_status(:created)
    expect do
      post "#{base}/tickets", headers: headers, params: input, as: :json
      expect(response).to have_http_status(:created)
    end.not_to(change { [JrcServiceDesk::Ticket.count, JrcServiceDesk::TicketEvent.count] })
  end

  it 'rejects caller-supplied identity, queue and team instead of bypassing the intake domain' do
    %w[requester_id queue_id team_id].each do |field|
      expect do
        post "#{base}/tickets", headers: headers, params: input.deep_merge(ticket: { field => observer.account_user_id.to_s }), as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end.not_to change(JrcServiceDesk::Ticket, :count)
    end
  end

  it 'offers only eligible people in the unit and persists the chosen recipient with safe replay' do
    outsider = create(:jrc_sd_membership, unit: sd_other_unit)
    context = JrcServiceDesk::UiContextService.new(user_context: sd_context).call
    intake = context[:units].find { |row| row[:id] == sd_unit.id.to_s }.fetch(:internal_intake)
    expect(intake[:assignees].pluck(:id)).to contain_exactly(sd_account_user.id.to_s, observer.account_user_id.to_s)
    chosen = input.deep_merge(ticket: { assignee_account_user_id: observer.account_user_id.to_s })
    2.times do
      post "#{base}/tickets", headers: headers, params: chosen, as: :json
      expect(response).to have_http_status(:created), response.body
    end
    expect(JrcServiceDesk::Ticket.where(account: sd_account).sole.assignee_membership_id).to eq(observer.id)
    post "#{base}/tickets", headers: headers, params: input, as: :json
    expect(response).to have_http_status(:conflict)
    post "#{base}/tickets", headers: headers.merge('Idempotency-Key' => 'foreign-recipient'),
      params: input.deep_merge(ticket: { assignee_account_user_id: outsider.account_user_id.to_s }), as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcServiceDesk::Ticket.where(account: sd_account).count).to eq(1)
  end

  it 'rechecks a selected recipient eligibility before creating the ticket' do
    observer.update!(manual_assignment_enabled: false)
    expect do
      post "#{base}/tickets", headers: headers,
        params: input.deep_merge(ticket: { assignee_account_user_id: observer.account_user_id.to_s }), as: :json
      expect(response).to have_http_status(:forbidden)
    end.not_to change(JrcServiceDesk::Ticket, :count)
  end

  it 'lets a native agent open a request for a recipient in another department of the same unit' do
    department = create(:team, account: sd_account)
    recipient = create(:jrc_sd_membership, unit: sd_unit, manual_assignment_enabled: true, team: department)
    create(:team_member, team: department, user: recipient.account_user.user)
    context = JrcServiceDesk::UiContextService.new(user_context: sd_context).call
    intake = context[:units].find { |row| row[:id] == sd_unit.id.to_s }.fetch(:internal_intake)
    expect(intake[:assignees].pluck(:id)).to include(recipient.account_user_id.to_s)

    chosen = input.deep_merge(ticket: { assignee_account_user_id: recipient.account_user_id.to_s })
    post "#{base}/tickets", headers: headers, params: chosen, as: :json
    expect(response).to have_http_status(:created), response.body
    ticket = JrcServiceDesk::Ticket.find_by!(account: sd_account, idempotency_key: 'synthetic-internal-intake')
    expect(ticket).to have_attributes(team_id: department.id, queue_id: nil, assignee_membership_id: recipient.id)
    recipient_context = { account: sd_account, user: recipient.account_user.user, account_user: recipient.account_user }
    expect(JrcServiceDesk::TicketPolicy.new(recipient_context, ticket).show?).to be(true)
    expect(JrcServiceDesk::TicketPolicy.new(sd_context, ticket).show?).to be(true)
    expect(JrcServiceDesk::TicketPolicy.new({ account: sd_account, user: observer_user, account_user: observer_member }, ticket).show?).to be(false)
    expect(ticket.ticket_events.where(event_type: 'resource_updated').sole.data).to eq('internal_request' => true)
  end

  it 'opens for an explicitly chosen unit agent without requiring legacy triage configuration' do
    sd_account.update!(internal_attributes: sd_account.internal_attributes.except(JrcServiceDesk::InternalIntake::KEY))
    context = JrcServiceDesk::UiContextService.new(user_context: sd_context).call
    intake = context[:units].find { |row| row[:id] == sd_unit.id.to_s }.fetch(:internal_intake)
    expect(intake[:primary]).to be_nil
    expect(intake[:assignees].pluck(:id)).to include(observer.account_user_id.to_s)
    post "#{base}/tickets", headers: headers,
      params: input.deep_merge(ticket: { assignee_account_user_id: observer.account_user_id.to_s }), as: :json
    expect(response).to have_http_status(:created), response.body
    ticket = JrcServiceDesk::Ticket.find_by!(account: sd_account, idempotency_key: 'synthetic-internal-intake')
    expect(ticket).to have_attributes(queue_id: nil, team_id: nil, assignee_membership_id: observer.id)
    expect(ticket.requester.email).to eq(sd_user.email)
  end

  it 'uses the authenticated employee identity without requiring commercial access to their own internal company contact' do
    company = sd_account.master_companies.create!(name: 'Synthetic employer', relationship_type: 'internal')
    contact = create(:contact, account: sd_account, email: sd_user.email, company_id: company.id,
      additional_attributes: { entity_type: 'person' })
    context = JrcServiceDesk::OperationalContext.new(sd_context)
    expect(JrcServiceDesk::RequesterDirectory.new(context).visible_contacts).not_to include(contact)
    post "#{base}/tickets", headers: headers,
      params: input.deep_merge(ticket: { assignee_account_user_id: observer.account_user_id.to_s }), as: :json
    expect(response).to have_http_status(:created), response.body
    expect(JrcServiceDesk::Ticket.find_by!(account: sd_account, idempotency_key: 'synthetic-internal-intake').requester_id).to eq(contact.id)
    expect(JrcServiceDesk::RequesterDirectory.new(context).visible_contacts).not_to include(contact)
  end

  it 'keeps the module and explicit recipient available when the configured primary cannot receive assignments' do
    sd_membership.update!(manual_assignment_enabled: false)
    get "#{base}/ui_context", headers: headers
    expect(response).to have_http_status(:ok), response.body
    post "#{base}/tickets", headers: headers,
      params: input.deep_merge(ticket: { assignee_account_user_id: observer.account_user_id.to_s }), as: :json
    expect(response).to have_http_status(:created), response.body
  end

  it 'does not expose the intake directory to a custom role without creation permission' do
    role = create(:custom_role, account: sd_account, permissions: %w[jrc_service_desk_module_view jrc_service_desk_tickets_view])
    sd_account_user.update!(custom_role_id: role.id)
    context = JrcServiceDesk::UiContextService.new(user_context: sd_context).call
    unit = context[:units].find { |row| row[:id] == sd_unit.id.to_s }
    expect(unit[:permissions][:create_ticket]).to be(false)
    expect(unit[:internal_intake]).to be_nil
    expect do
      post "#{base}/tickets", headers: headers,
        params: input.deep_merge(ticket: { assignee_account_user_id: observer.account_user_id.to_s }), as: :json
      expect(response).to have_http_status(:not_found)
    end.not_to change(JrcServiceDesk::Ticket, :count)
  end

  it 'rejects the selected recipient when their explicitly configured queue has been deactivated' do
    department = create(:team, account: sd_account)
    target_queue = create(:jrc_sd_queue, unit: sd_unit, team: department)
    recipient = create(:jrc_sd_membership, unit: sd_unit, manual_assignment_enabled: true, team: department, queue: target_queue)
    create(:team_member, team: department, user: recipient.account_user.user)
    target_queue.update!(active: false)
    expect do
      post "#{base}/tickets", headers: headers,
        params: input.deep_merge(ticket: { assignee_account_user_id: recipient.account_user_id.to_s }), as: :json
      expect(response).to have_http_status(:forbidden)
    end.not_to change(JrcServiceDesk::Ticket, :count)
  end

  it 'denies another unit and another account through the same API' do
    [sd_other_unit, sd_foreign_unit].each do |unit|
      expect do
        post "#{base}/tickets", headers: headers, params: input.merge(unit_id: unit.id.to_s), as: :json
        expect(response).to have_http_status(:not_found)
      end.not_to change(JrcServiceDesk::Ticket, :count)
    end
  end

  it 'rechecks the configured primary membership at execution time' do
    sd_membership.update!(manual_assignment_enabled: false)
    expect do
      post "#{base}/tickets", headers: headers, params: input, as: :json
      expect(response).to have_http_status(:forbidden)
    end.not_to change(JrcServiceDesk::Ticket, :count)
  end

  it 'refuses another account queue in the internal configuration' do
    foreign = create(:jrc_sd_queue, unit: sd_foreign_unit)
    values = sd_account.internal_attributes.deep_dup
    values[JrcServiceDesk::InternalIntake::KEY][sd_unit.id.to_s]['queue_id'] = foreign.id.to_s
    sd_account.update!(internal_attributes: values)
    expect do
      post "#{base}/tickets", headers: headers, params: input, as: :json
      expect(response).to have_http_status(:not_found)
    end.not_to change(JrcServiceDesk::Ticket, :count)
  end
end

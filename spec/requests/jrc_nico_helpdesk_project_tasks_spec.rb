require 'rails_helper'

# Capture, worker, human approval, native Projects persistence and authenticated GET.
RSpec.describe 'HelpDesk R02/R07 native Project tasks', type: :request do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures

  let(:selected_rule) { 'R02' }
  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'Synthetic root-cause company') }
  let(:ticket) { sd_ticket(company_id: company.id) }
  let(:headers) { sd_user.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_nico/helpdesk" }
  let(:definition) do
    value = JrcNico::Helpdesk::Definition.defaults.merge('unit_ids' => [sd_unit.id], 'company_ids' => [company.id],
                                                         'operator_ids' => [sd_account_user.id])
    value['rules'][selected_rule]['enabled'] = true
    value['rules'][selected_rule]['confirmed'] = true if value['rules'][selected_rule].key?('confirmed')
    value
  end
  let(:policy) do
    JrcNico::Helpdesk::PolicyVersion.create!(account: sd_account, author: sd_account_user, number: 1,
                                             state: 'published', enabled: true, published_at: Time.current, definition: definition,
                                             digest: JrcNico::Helpdesk::Definition.digest(definition))
  end
  let(:approvals) { JrcNico::Helpdesk::Approvals.new(sd_account_user) }

  before do
    travel_to Time.iso8601('2026-10-08T12:00:00Z')
    sd_account.update!(custom_attributes: { 'nico_enabled' => true })
    sd_account.enable_features!('jrc_projects', 'jrc_customer_master')
    sd_account_user.update!(jrc_projects_enabled: true)
    sd_as_admin!
  end

  def profile(row)
    JrcNico::Helpdesk::TicketProfile.create!(account: sd_account, unit: sd_unit, ticket: row,
                                             company_id: company.id, case_kind: 'defect', defect_key: 'voice.trunk')
  end

  def captured_event
    prepare_native_task_source
    policy
    events = JrcNico::Helpdesk::Capture.new(sd_account_user).call(ticket: ticket, trigger: 'monitor',
                                                                  origin_key: "native-task:#{ticket.id}")
    expect(events.map(&:rule_key)).to eq([selected_rule])
    event = events.fetch(0)
    JrcNico::Helpdesk::EventJob.perform_now(event.id)
    expect(event.reload.state).to eq('prepared')
    event
  end

  def prepare_native_task_source
    profile(ticket)
    if selected_rule == 'R02'
      2.times { profile(sd_ticket(company_id: company.id, opened_at: 2.days.ago)) }
    else
      prepare_overdue_native_clock
    end
  end

  def prepare_overdue_native_clock
    lc_publish(definition: lc_definition(tracked: true))
    lc_snapshot(ticket)
    lc_execute(ticket, 'work_status')
    clock = ticket.reload.sla_cycles.last.sla_clocks.find_by!(kind: 'resolution')
    travel_to(clock.due_at + 24.hours + 1.second, with_usec: true)
  end

  def approved_project(event)
    approval = approvals.prepare(event_id: event.id, tool: 'create_project',
                                 arguments: { 'ticket_id' => ticket.id, 'name' => 'Root-cause action plan' })
    expect(approvals.approve(id: approval.id, payload_digest: approval.payload_digest).state).to eq('succeeded')
    JrcProjects::Project.find(approval.command.reload.result.dig('record', 'id'))
  end

  def arguments(project)
    { 'ticket_id' => ticket.id, 'project_id' => project.id,
      'board_column_id' => project.board_columns.find_by!(status_key: 'backlog').id,
      'title' => 'Investigate the captured defect', 'estimated_minutes' => 0 }
  end

  def verify_native_task_receipt(command, project)
    expect(command).to have_attributes(status: 'succeeded', tool: 'create_project_task')
    expect(command.result['resource_type']).to eq('JrcProjects::Task')
    expect(command.result).not_to have_key('browser_action')
    task = JrcProjects::Task.find(command.result.dig('record', 'id'))
    expect(task).to have_attributes(account_id: sd_account.id, project_id: project.id, created_by_id: sd_user.id,
                                    title: 'Investigate the captured defect', status: 'backlog', estimated_minutes: 0)
    link = task.operation_links.find_by!(ticket_id: ticket.id)
    expect(link).to have_attributes(ticket_unit_id: sd_unit.id, account_id: sd_account.id, project_id: project.id)
    audit = JrcProjects::AuditEvent.find_by!(action: 'projects.task.created', auditable_type: task.class.name, auditable_id: task.id)
    expect(audit).to have_attributes(actor_id: sd_user.id, correlation_id: "nico_#{command.id}_#{command.request_id}")
    task
  end

  def verify_native_task_readback(project, task, prepared)
    get "/api/v1/accounts/#{sd_account.id}/projects/projects/#{project.id}/tasks/#{task.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('data')).to include('id' => task.id, 'project_id' => project.id, 'title' => task.title)
    get "#{base}/approvals", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('approvals').pluck('id')).to include(prepared.id)
    sd_membership.update!(active: false)
    get "#{base}/approvals", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('approvals')).to be_empty
    expect(task.reload).to be_persisted
  end

  %w[R02 R07].each do |key|
    context "with #{key}" do
      let(:selected_rule) { key }

      it 'persists and reloads the real Project Task once through the existing complete approval chain' do
        event = captured_event
        project = approved_project(event)
        prepared = approvals.prepare(event_id: event.id, tool: 'create_project_task', arguments: arguments(project))
        expect { approvals.approve(id: prepared.id, payload_digest: prepared.payload_digest) }
          .to change(JrcProjects::Task, :count).by(1)
        command = prepared.command.reload
        task = verify_native_task_receipt(command, project)
        counts = [JrcProjects::Task.count, JrcOperations::Link.count, JrcProjects::AuditEvent.count]
        approvals.approve(id: prepared.id, payload_digest: prepared.payload_digest)
        expect([JrcProjects::Task.count, JrcOperations::Link.count, JrcProjects::AuditEvent.count]).to eq(counts)
        verify_native_task_readback(project, task, prepared)
      end
    end
  end

  it 'rejects an unrelated project, even when its native Project grants allow writing' do
    event = captured_event
    project = JrcProjects::Projects::Create.call(account: sd_account, actor: sd_user, attributes: { name: 'Unrelated' },
                                                 idempotency_key: SecureRandom.uuid)
    expect { approvals.prepare(event_id: event.id, tool: 'create_project_task', arguments: arguments(project)) }
      .to raise_error(Pundit::NotAuthorizedError)
    expect(JrcProjects::Task.where(project: project)).to be_empty
  end

  it 'rechecks the exact Unit and native project permission before execution and source readback' do
    event = captured_event
    project = approved_project(event)
    value = approvals.prepare(event_id: event.id, tool: 'create_project_task', arguments: arguments(project))
    role = create(:custom_role, account: sd_account,
                                permissions: %w[jrc_service_desk_module_view jrc_service_desk_tickets_view jrc_projects_project_view jrc_projects_task_view])
    sd_account_user.update!(custom_role: role)
    expect { approvals.approve(id: value.id, payload_digest: value.payload_digest) }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcProjects::Task.where(project: project)).to be_empty
    expect(value.reload.state).to eq('pending')
  end
end

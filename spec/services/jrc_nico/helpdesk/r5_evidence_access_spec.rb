# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcNico::Helpdesk::Context do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'R5 evidence fixture') }
  let(:ticket) { sd_ticket(company_id: company.id) }
  let(:policy) do
    definition = JrcNico::Helpdesk::Definition.defaults.merge('unit_ids' => [sd_unit.id], 'company_ids' => [company.id],
                                                              'operator_ids' => [sd_account_user.id])
    JrcNico::Helpdesk::PolicyVersion.create!(account: sd_account, author: sd_account_user, number: 1, state: 'draft', enabled: false,
                                             definition: definition, digest: JrcNico::Helpdesk::Definition.digest(definition))
  end

  before do
    sd_account.update!(custom_attributes: { 'nico_enabled' => true })
    sd_account.enable_features!('jrc_relationship', 'jrc_customer_master', 'jrc_crm')
    sd_as_admin!
  end

  def captured_event(rule, evidence)
    JrcNico::Helpdesk::Event.create!(account: sd_account, actor: sd_account_user, policy_version: policy, ticket: ticket,
                                     rule_key: rule, correlation_key: SecureRandom.uuid, detected_at: Time.current, evidence: evidence)
  end

  def restrict_native_role(except:)
    permissions = JrcServiceDesk::Capabilities::DEFAULTS.fetch('administrator') - Array(except)
    role = create(:custom_role, account: sd_account, permissions: permissions.map { |key| "jrc_service_desk_#{key}" })
    sd_account_user.update!(role: :agent, custom_role: role)
    role
  end

  def resolution_clock(row = ticket)
    lc_snapshot(row)
    lc_publish(definition: lc_definition(tracked: true))
    lc_execute(row, 'work_status')
    row.sla_cycles.order(number: :desc).first.sla_clocks.find_by!(kind: 'resolution')
  end

  it 'revalidates the current SLA grant even when a clock was captured under a different rule' do
    event = captured_event('R13', 'clock_id' => resolution_clock.id)
    context = described_class.new(sd_account_user)
    expect(context.event(event.id)).to eq(event)
    restrict_native_role(except: 'sla_view')
    expect { context.event(event.id) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rejects a same-account clock from another ticket before disclosing the evidence' do
    other = sd_ticket(company_id: company.id)
    event = captured_event('R13', 'clock_id' => resolution_clock(other).id)
    expect { described_class.new(sd_account_user).event(event.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  def shared_survey_definition
    JrcRelationship::SurveyDefinition.create!(account: sd_account, name: 'R5 shared NPS', code: 'r5_shared_nps',
                                              kind: 'nps', status: 'active', questions: [{ 'key' => 'rating', 'text' => 'Service rating',
                                                                                           'type' => 'scale', 'min' => 0, 'max' => 10,
                                                                                           'required' => true }])
  end

  def prepare_shared_survey
    sd_contact.update!(company_id: company.id, email: 'r5-survey@example.test', custom_attributes: { 'survey_consent' => true })
    JrcRelationship::Assignment.create!(account: sd_account, company: company, owner: sd_user, status: 'active')
    JrcRelationship::Configuration.create!(account: sd_account, rules: { survey_automation_enabled: true })
    JrcRelationship::SurveyRule.create!(account: sd_account, name: 'R5 shared closure', definition: shared_survey_definition,
                                        execution_member: sd_account_user, active: true, matchers: { 'source_type' => ticket.class.name },
                                        settings: { 'channel' => 'public_link' })
  end

  def shared_survey_decision
    prepare_shared_survey
    lc_publish
    lc_execute(ticket, 'resolve')
    lc_execute(ticket, 'close')
    cycle = "service-desk:ticket:#{ticket.id}:cycle:initial"
    JrcRelationship::SurveyDispatchDecision.find_by!(account: sd_account, source_type: ticket.class.name,
                                                     source_id: ticket.id, cycle_key: cycle)
  end

  it 'reuses the shared survey decision and revalidates current relationship authority on event readback' do
    decision = shared_survey_decision
    expect(decision.state).to eq('scheduled')
    event = captured_event('R15', 'survey_decision_id' => decision.id, 'cycle_key' => decision.cycle_key)
    context = described_class.new(sd_account_user)
    expect { context.event(event.id) }.not_to change(JrcRelationship::Survey, :count)
    restrict_native_role(except: [])
    expect { context.event(event.id) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rechecks the protected survey source even when R15 contains only the native decision ID' do
    decision = shared_survey_decision
    event = captured_event('R15', 'survey_decision_id' => decision.id, 'cycle_key' => decision.cycle_key)
    role = restrict_native_role(except: [])
    role.update!(permissions: role.permissions + %w[contact_manage jrc_relationship_view])
    context = described_class.new(sd_account_user)
    expect(context.event(event.id)).to eq(event)
    other = create(:user, account: sd_account, role: :agent)
    JrcRelationship::Assignment.find_by!(account: sd_account, company: company).update!(owner: other)
    expect { context.event(event.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(context.ticket(ticket.id)).to eq(ticket)
  end

  it 'does not trust a foreign survey decision ID or fabricate a customer return cycle' do
    event = captured_event('R15', 'survey_decision_id' => 999_999_999, 'cycle_key' => 'invented-cycle')
    expect { described_class.new(sd_account_user).event(event.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcRelationship::Survey.where(account: sd_account)).to be_empty
  end
end

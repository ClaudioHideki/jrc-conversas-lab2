# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk calendar preview HTTP contract', type: :request do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  include ActiveSupport::Testing::TimeHelpers

  let(:root) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/automation_publications/preview" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:queue) { create(:jrc_sd_queue, unit: sd_unit, distribution_mode: 'manual') }
  let(:periods) { [['08:00', '12:00'], ['13:00', '18:00']] }
  let(:calendar) do
    { 'format' => 'jrc-sd-snapshot-calendar-v1',
      'weekly' => (1..7).to_h { |day| [day.to_s, day <= 5 ? periods.deep_dup : []] },
      'holidays' => ['2026-10-27'],
      'exceptions' => { '2026-10-27' => [['10:00', '11:00'], ['14:00', '16:00']] } }
  end
  let(:definition) do
    lc_definition(tracked: true).tap do |value|
      value['schema_version'] = 2
      value['sla']['escalation_policy'] = {}
      value['transitions'].each do |transition|
        transition['clocks']['attendance'] = %w[resolve work_status].include?(transition['action']) ? 'complete' : 'keep'
      end
      value['pause_reasons'].first['clocks'] = %w[attendance resolution]
      value['reopen']['resume_clocks'] = %w[attendance resolution]
    end
  end
  let(:budgets) { { 'first_response' => 1800, 'attendance' => 3600, 'resolution' => 14_400 } }
  let(:snapshot) do
    sd_snapshot_attributes.deep_stringify_keys.except('captured_at').merge(
      'calendar_conditions' => calendar.deep_dup, 'policy_conditions' => { 'clock_budgets_seconds' => budgets.deep_dup }
    )
  end
  let(:attributes) do
    { 'kind' => 'lifecycle', 'code' => 'calendar-http-contract', 'name' => 'Synthetic calendar contract',
      'description' => 'Local calendar preview only', 'service_id' => nil, 'enabled' => false,
      'definition' => { 'lifecycle' => definition, 'notifications' => [],
        'families' => { 'sla_selection' => { 'rules' => [{ 'key' => 'explicit-calendar', 'precedence' => 1,
          'match' => { 'priority_id' => sd_priority.id }, 'output' => { 'snapshot' => snapshot } }] } },
        'queues' => [{ 'id' => queue.id, 'attributes' => {
          'ola_targets' => { 'first_response' => 900, 'update' => 1800, 'resolution' => 7200 },
          'ola_time_basis' => 'business',
          'ola_calendar' => { 'timezone' => 'America/Sao_Paulo', 'conditions' => calendar.deep_dup }
        } }] } }
  end
  let(:observed_models) do
    [JrcServiceDesk::AutomationPublication, JrcServiceDesk::LifecyclePolicyVersion, JrcServiceDesk::OperationalRuleVersion,
     JrcServiceDesk::QueuePolicyVersion, JrcServiceDesk::UnitMembership, JrcServiceDesk::Ticket,
     JrcServiceDesk::TicketEvent, JrcServiceDesk::SlaSnapshot, JrcServiceDesk::SlaCycle,
     JrcServiceDesk::SlaClock, JrcServiceDesk::OlaClock, JrcServiceDesk::NotificationDelivery, Audited::Audit, Message]
  end

  before do
    travel_to Time.iso8601('2026-10-26T11:30:00Z')
    sd_as_admin!
  end

  after { travel_back }

  it 'accepts exact period pairs and preserves schema two, all three clock budgets and existing historical deadlines' do
    version = lc_publish(definition: definition).current_version
    historical = sd_ticket(lifecycle_policy_version: version, opened_at: Time.iso8601('2026-10-26T11:00:00Z'))
    JrcServiceDesk::RecordSlaSnapshotService.new(user_context: sd_context).call(ticket_id: historical.id,
      attributes: snapshot.merge('captured_at' => '2026-10-26T11:00:00Z'))
    lc_execute(historical, 'work_status')
    input = { unit_id: sd_unit.id, attributes: attributes, facts: {}, at: '2026-10-26T11:30:00Z' }
    native_headers = headers
    counts = observed_models.map(&:count)
    clocks = historical.sla_cycles.sole.sla_clocks.order(:kind).map(&:attributes)
    ticket = historical.reload.attributes
    queue_before = queue.reload.attributes
    job_count = enqueued_jobs.size

    post root, headers: native_headers, as: :json, params: input

    expect(response).to have_http_status(:ok), response.body
    body = request.request_parameters.fetch('attributes')
    received = body.dig('definition', 'families', 'sla_selection', 'rules', 0, 'output', 'snapshot')
    received_calendar = received.fetch('calendar_conditions')
    expect(received_calendar.fetch('weekly').fetch('1')).to eq(periods)
    expect(received_calendar.fetch('weekly').fetch('6')).to eq([])
    expect(received_calendar.fetch('exceptions')).to eq(calendar.fetch('exceptions'))
    rows = received_calendar.fetch('weekly').values + received_calendar.fetch('exceptions').values
    expect(rows.flatten(1)).to all(satisfy { |pair| pair.is_a?(Array) && pair.size == 2 && pair.all?(String) })
    expect(body.dig('definition', 'lifecycle', 'schema_version')).to eq(2)
    expect(received.dig('policy_conditions', 'clock_budgets_seconds')).to eq(budgets)
    expect(body.dig('definition', 'queues', 0, 'attributes', 'ola_calendar', 'conditions')).to eq(calendar)
    expect(body.dig('definition', 'queues', 0, 'attributes', 'ola_targets')).to eq(
      'first_response' => 900, 'update' => 1800, 'resolution' => 7200
    )
    preview = response.parsed_body.fetch('preview')
    expect(preview.fetch('valid')).to be(true)
    expect(preview.fetch('sla_deadlines').sole.fetch('due_at')).to eq(
      'first_response' => '2026-10-26T12:00:00Z', 'attendance' => '2026-10-26T12:30:00Z', 'resolution' => '2026-10-26T16:30:00Z'
    )
    expect(preview.fetch('effects').values).to all(be(false))
    expect(preview.fetch('historical_tickets_changed')).to eq(0)
    expect(observed_models.map(&:count)).to eq(counts)
    expect(historical.reload.attributes).to eq(ticket)
    expect(historical.sla_cycles.sole.sla_clocks.order(:kind).map(&:attributes)).to eq(clocks)
    expect(historical.sla_cycles.sole.sla_clocks.pluck(:kind).sort).to eq(%w[attendance first_response resolution])
    expect(queue.reload.attributes).to eq(queue_before)
    expect(enqueued_jobs.size).to eq(job_count)
  end

  it 'uses explicit exception pairs over a holiday without publishing, scheduling or changing the queue' do
    input = { unit_id: sd_unit.id, attributes: attributes, facts: {}, at: '2026-10-27T12:30:00Z' }
    native_headers = headers
    counts = observed_models.map(&:count)
    queue_before = queue.reload.attributes
    job_count = enqueued_jobs.size

    post root, headers: native_headers, as: :json, params: input

    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.dig('preview', 'sla_deadlines').sole.fetch('due_at')).to eq(
      'first_response' => '2026-10-27T13:30:00Z', 'attendance' => '2026-10-27T14:00:00Z', 'resolution' => '2026-10-28T12:00:00Z'
    )
    expect(observed_models.map(&:count)).to eq(counts)
    expect(queue.reload.attributes).to eq(queue_before)
    expect(enqueued_jobs.size).to eq(job_count)
  end

  {
    'the old semicolon parser three-element pair' => [['08:00', '12:00;13:00', '18:00']],
    'raw interval text instead of explicit JSON pairs' => '08:00-12:00;13:00-18:00',
    'overlapping pairs' => [['08:00', '12:00'], ['11:00', '18:00']],
    'a malformed exception pair' => [['10:00', '11:00', '16:00']]
  }.each do |description, malformed|
    it "rejects #{description} with 422 instead of weakening calendar validation" do
      input = attributes.deep_dup
      key = description.include?('exception') ? 'exceptions' : 'weekly'
      day = key == 'exceptions' ? '2026-10-27' : '1'
      input['definition']['families']['sla_selection']['rules'].first['output']['snapshot']['calendar_conditions'][key][day] = malformed
      native_headers = headers
      counts = observed_models.map(&:count)
      job_count = enqueued_jobs.size

      post root, headers: native_headers, as: :json, params: { unit_id: sd_unit.id, attributes: input, facts: {} }

      expect(response).to have_http_status(:unprocessable_entity), response.body
      expect(response.parsed_body.fetch('code')).to eq('invalid_input')
      expect(observed_models.map(&:count)).to eq(counts)
      expect(enqueued_jobs.size).to eq(job_count)
    end
  end

  it 'rejects an invalid OLA calendar independently of the valid external SLA calendar' do
    input = attributes.deep_dup
    input['definition']['queues'].first['attributes']['ola_calendar']['conditions']['weekly']['1'] = [['18:00', '08:00']]
    native_headers = headers
    counts = observed_models.map(&:count)
    queue_before = queue.reload.attributes

    post root, headers: native_headers, as: :json, params: { unit_id: sd_unit.id, attributes: input, facts: {} }

    expect(response).to have_http_status(:unprocessable_entity), response.body
    expect(response.parsed_body.fetch('code')).to eq('validation_failed')
    expect(response.parsed_body.fetch('fields')).to include('ola_calendar')
    expect(observed_models.map(&:count)).to eq(counts)
    expect(queue.reload.attributes).to eq(queue_before)
  end

  %w[missing_attendance unexpected_fourth].each do |change|
    it "rejects #{change} clock budgets without dropping attendance or adding a fourth clock" do
      input = attributes.deep_dup
      values = input['definition']['families']['sla_selection']['rules'].first['output']['snapshot']['policy_conditions']['clock_budgets_seconds']
      if change == 'missing_attendance'
        values.delete('attendance')
      else
        values['waiting'] = 300
      end
      native_headers = headers
      counts = observed_models.map(&:count)

      post root, headers: native_headers, as: :json, params: { unit_id: sd_unit.id, attributes: input, facts: {} }

      expect(response).to have_http_status(:unprocessable_entity), response.body
      expect(response.parsed_body.fetch('code')).to eq('invalid_input')
      expect(observed_models.map(&:count)).to eq(counts)
    end
  end
end

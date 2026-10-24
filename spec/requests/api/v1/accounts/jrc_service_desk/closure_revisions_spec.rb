# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'Administrative prospective closure revisions', type: :request do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  include ActiveSupport::Testing::TimeHelpers
  let(:root) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:sd_category) { create(:jrc_sd_category, unit: sd_unit) }
  let(:old_definition) do
    definition = lc_definition(tracked: true)
    definition['transitions'].each do |rule|
      next unless %w[resolve close].include?(rule['action'])
      rule['requirements'].merge!('note' => true, 'solution' => true, 'classification' => true)
      rule['requirements']['fields']['closing_reason'] = { 'type' => 'text', 'required' => true, 'label' => 'Motivo antigo' } if rule['action'] == 'close'
    end
    definition
  end
  let(:source) { lc_publish(definition: old_definition).current_version }
  let(:definition) { JrcServiceDesk::ClosureRevisionBinding.proposal(source) }
  let(:target) { lc_publish(definition: definition, expected_version: 1).current_version }
  before do
    travel_to Time.iso8601('2026-10-23T13:00:00Z')
    sd_as_admin!
    source
    target
  end
  after { travel_back }

  def preview(tickets, review: true, source_id: source.id, target_id: target.id)
    post "#{root}/closure_revisions/preview", headers: headers, as: :json,
      params: { unit_id: sd_unit.id, source_version_id: source_id, target_version_id: target_id,
        ticket_ids: tickets.map(&:id), operational_review: review, review_reason: 'Escopo operacional revisado explicitamente em fixture sintética.' }
    response.parsed_body['preview']
  end

  def apply(receipt, key: 'synthetic-revision-batch')
    post "#{root}/closure_revisions", headers: headers.merge('Idempotency-Key' => key), as: :json,
      params: { unit_id: sd_unit.id, receipt: receipt }
    response.parsed_body['result']
  end

  def snapshot(ticket, contract: {})
    settings = sd_snapshot_attributes.merge(contract_conditions: contract,
      policy_conditions: { clock_budgets_seconds: source.rules.clock_kinds.to_h { |kind| [kind, { 'first_response' => 7200, 'resolution' => 28800, 'attendance' => 3600 }.fetch(kind)] } },
      calendar_conditions: { format: JrcServiceDesk::SnapshotCalendar::VERSION,
        weekly: (1..7).to_h { |day| [day.to_s, day <= 5 ? [['09:00', '17:00']] : []] }, holidays: [], exceptions: {} })
    JrcServiceDesk::RecordSlaSnapshotService.new(user_context: sd_context).call(ticket_id: ticket.id, attributes: settings)
  end

  it 'previews and applies only future closure requirements, keeping the original policy and complete ticket state' do
    ticket = sd_ticket(lifecycle_policy_version: source)
    before = ticket.attributes.except('updated_at', 'lock_version')
    definition_before = source.attributes.deep_dup
    get "#{root}/tickets/#{ticket.id}/lifecycle", headers: headers
    expect(response.parsed_body['closure_options']).to be_empty
    approved = preview([ticket])
    expect(response).to have_http_status(:ok)
    expect(approved['eligible']).to eq(1)
    result = apply(approved['receipt'])
    expect(response).to have_http_status(:created)
    expect(result['results'].sole['status']).to eq('applied')
    expect(ticket.reload.attributes.except('updated_at', 'lock_version')).to eq(before)
    expect(source.reload.attributes).to eq(definition_before)
    expect(ticket.lifecycle_policy_version_id).to eq(source.id)
    expect(ticket.sla_cycles.count).to eq(0)
    get "#{root}/tickets/#{ticket.id}/lifecycle", headers: headers
    expect(response.parsed_body.dig('policy', 'id')).to eq(source.id.to_s)
    expect(response.parsed_body.dig('closure_revision', 'target_version_id')).to eq(target.id.to_s)
    expect(response.parsed_body['closure_options'].sole['steps'].map { |r| r['requirements'] }).to all(include('note' => false, 'solution' => false, 'classification' => false))
    %w[resolve close].each do |action|
      lc_execute(ticket, action, closing_reason: 'Atendimento encerrado pelo motivo real', fields: { closing_reason: 'Atendimento encerrado pelo motivo real' })
    end
    expect(ticket.reload.status.phase).to eq('closed')
    expect(ticket.lifecycle_transitions.map(&:lifecycle_policy_version_id)).to eq([source.id, source.id])
    expect(ticket.lifecycle_transitions.map { |r| r.payload.dig('closure_revision', 'target_version_id') }).to eq([target.id.to_s] * 2)
    expect(ticket.lifecycle_transitions.map { |r| r.payload.dig('closure_revision', 'active') }).to eq([true, true])
    get "#{root}/tickets/#{ticket.id}/lifecycle", headers: headers
    expect(response.parsed_body.dig('closure_revision', 'active')).to be(false)
    expect(ticket.lifecycle_transitions.map { |r| r.payload.dig('sla', 'calculation_pending') }).to eq([true, true])
    expect(ticket.sla_cycles.count).to eq(0)
    expect(ticket.lifecycle_transitions.none? { |r| r.payload['note'] || r.payload['solution'] }).to be(true)
  end

  it 'requires explicit classification and never writes an audit or ticket from a rejected preview' do
    ticket = sd_ticket(lifecycle_policy_version: source)
    expect { preview([ticket], review: false) }.not_to change(Audited::Audit, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(ticket.reload.lock_version).to eq(0)
    expect(ticket.ticket_events.count).to eq(0)
  end

  it 'prepares the proposed definition as a draft and publishes a new version through the official publisher' do
    post "#{root}/closure_revisions/proposal", headers: headers, as: :json, params: { unit_id: sd_unit.id, source_version_id: source.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['definition']).to eq(definition)
    expect(response.parsed_body['expected_version']).to eq(2)
    expect(source.reload.version).to eq(1)
    expect(JrcServiceDesk::LifecyclePolicyVersion.count).to eq(2)
  end

  it 'preserves a paused and overdue cycle, snapshot, first response and historical timestamps during application' do
    ticket = sd_ticket(lifecycle_policy_version: source)
    snapshot(ticket)
    lc_execute(ticket, 'work_status')
    travel 3.days + 2.hours
    lc_execute(ticket, 'pause', reason_code: 'customer')
    clocks = ticket.sla_cycles.sole.sla_clocks.order(:id).map(&:attributes)
    pauses = ticket.lifecycle_pauses.order(:id).map(&:attributes)
    snapshots = ticket.sla_snapshots.map(&:attributes)
    history = ticket.lifecycle_transitions.map(&:attributes)
    approved = preview([ticket])
    expect(approved['eligible']).to eq(1)
    expect(apply(approved['receipt'])['results'].sole['status']).to eq('applied')
    expect(ticket.reload.sla_cycles.sole.sla_clocks.order(:id).map(&:attributes)).to eq(clocks)
    expect(ticket.lifecycle_pauses.order(:id).map(&:attributes)).to eq(pauses)
    expect(ticket.sla_snapshots.map(&:attributes)).to eq(snapshots)
    expect(ticket.lifecycle_transitions.map(&:attributes)).to eq(history)
    lc_execute(ticket, 'resolve', closing_reason: 'Conclusão real', fields: { closing_reason: 'Conclusão real' })
    expect(ticket.sla_cycles.sole.sla_clocks.find_by!(kind: 'resolution').met?).to be(false)
    expect(ticket.sla_cycles.sole.sla_clocks.find_by!(kind: 'first_response').met?).to be_nil
  end

  it 'allows an already resolved ticket to close without replacing the earlier solution or transition' do
    ticket = sd_ticket(lifecycle_policy_version: source, category: sd_category)
    snapshot(ticket)
    resolved = lc_execute(ticket, 'resolve', solution: 'Solução histórica real', note: 'Nota histórica real')
    old = resolved.attributes.deep_dup
    approved = preview([ticket])
    expect(apply(approved['receipt'])['results'].sole['status']).to eq('applied')
    lc_execute(ticket, 'close', closing_reason: 'Motivo final', fields: { closing_reason: 'Motivo final' })
    expect(ticket.reload.status.phase).to eq('closed')
    expect(resolved.reload.attributes).to eq(old)
  end

  it 'leaves closed tickets unchanged and reports their explicit exclusion' do
    ticket = sd_ticket(lifecycle_policy_version: source, status: lc_statuses[:open])
    # Existing terminal state is established by the original authorized transitions.
    ticket.update!(category: sd_category)
    snapshot(ticket)
    lc_execute(ticket, 'resolve', solution: 'Solução anterior', note: 'Nota anterior')
    lc_execute(ticket, 'close', solution: 'Solução anterior', note: 'Nota anterior', fields: { closing_reason: 'Fechamento anterior' })
    before = ticket.reload.attributes.deep_dup
    events = ticket.ticket_events.map(&:attributes)
    approved = preview([ticket])
    expect(approved['tickets'].sole['reason']).to eq('terminal_ticket')
    expect(apply(approved['receipt'])['results'].sole['status']).to eq('blocked')
    expect(ticket.reload.attributes).to eq(before)
    expect(ticket.ticket_events.map(&:attributes)).to eq(events)
  end

  it 'excludes contractual snapshot conditions and mandatory service approvals' do
    contract_ticket = sd_ticket(lifecycle_policy_version: source)
    snapshot(contract_ticket, contract: { contract_validated: true })
    service = JrcServiceDesk::Service.create!(account: sd_account, unit: sd_unit, name: 'Serviço protegido', code: 'protected', active: true, approval_required: true)
    approval_ticket = sd_ticket(lifecycle_policy_version: source, service: service)
    approved = preview([contract_ticket, approval_ticket])
    expect(approved['blocked']).to eq(2)
    expect(apply(approved['receipt'])['results'].map { |r| r['reason'] }).to eq(['contractual_ticket'] * 2)
    expect(contract_ticket.ticket_events.where(event_type: 'closure_policy_revised').count).to eq(0)
    expect(approval_ticket.ticket_events.where(event_type: 'closure_policy_revised').count).to eq(0)
  end

  it 'does not infer an operational classification for explicit contractual or specific evidence requirements' do
    contractual = source.definition.deep_dup
    contractual['sla'].merge!('obligation' => 'contractual', 'missing_configuration' => 'block')
    policy = lc_publish(definition: contractual, expected_version: 2)
    expect { JrcServiceDesk::ClosureRevisionBinding.proposal(policy.current_version) }.to raise_error(ArgumentError)
    special = source.definition.deep_dup
    special['transitions'].find { |r| r['action'] == 'close' }['requirements']['evidence'] = true
    policy = lc_publish(definition: special, expected_version: 3)
    expect { JrcServiceDesk::ClosureRevisionBinding.proposal(policy.current_version) }.to raise_error(ArgumentError)
  end

  it 'reports version conflicts per ticket and replays the exact batch without duplicate mutation or events' do
    a, b = 2.times.map { sd_ticket(lifecycle_policy_version: source) }
    approved = preview([a, b])
    b.update!(title: 'Alterado após a prévia')
    result = apply(approved['receipt'])
    expect(result['results'].map { |r| r['status'] }).to eq(%w[applied conflict])
    count = Audited::Audit.count
    expect(apply(approved['receipt'])).to eq(result)
    expect(Audited::Audit.count).to eq(count)
    expect(a.ticket_events.where(event_type: 'closure_policy_revised').count).to eq(1)
    expect(b.ticket_events.where(event_type: 'closure_policy_revised').count).to eq(0)
    fresh = preview([b])
    expect(apply(fresh['receipt'], key: 'synthetic-conflict-recovery')['results'].sole['status']).to eq('applied')
  end

  it 'rolls back a failed item and resumes a partially committed batch without repeating successful items' do
    a, b = 2.times.map { sd_ticket(lifecycle_policy_version: source) }
    approved = preview([a, b])
    failed = false
    allow(JrcServiceDesk::TicketEvent).to receive(:create!).and_wrap_original do |method, **attrs|
      if attrs[:ticket].id == b.id && attrs[:event_type] == 'closure_policy_revised' && !failed
        failed = true
        raise ActiveRecord::RecordInvalid.new(b)
      end
      method.call(**attrs)
    end
    result = apply(approved['receipt'])
    expect(result['results'].map { |r| r['status'] }).to eq(%w[applied pending])
    expect(b.reload.lock_version).to eq(0)
    get "#{root}/closure_revisions/result", headers: headers, params: { unit_id: sd_unit.id, idempotency_key: 'synthetic-revision-batch' }
    expect(response.parsed_body['result']['complete']).to be(false)
    post "#{root}/closure_revisions/resume", headers: headers, as: :json, params: { unit_id: sd_unit.id, idempotency_key: 'synthetic-revision-batch' }
    expect(response.parsed_body['result']['results'].map { |r| r['status'] }).to eq(%w[applied applied])
    expect(a.ticket_events.where(event_type: 'closure_policy_revised').count).to eq(1)
    expect(b.ticket_events.where(event_type: 'closure_policy_revised').count).to eq(1)
  end

  it 'rejects forged, expired and foreign-actor previews without changing ticket bindings' do
    ticket = sd_ticket(lifecycle_policy_version: source)
    apply('invalid')
    expect(response).to have_http_status(:conflict)
    approved = preview([ticket])
    travel 16.minutes
    apply(approved['receipt'])
    expect(response).to have_http_status(:conflict)
    expect(ticket.reload.lock_version).to eq(0)
    travel(-16.minutes)
    other = create(:account_user, account: sd_account, role: :administrator)
    post "#{root}/closure_revisions", headers: other.user.create_new_auth_token.merge('Idempotency-Key' => 'other-actor'), as: :json,
      params: { unit_id: sd_unit.id, receipt: approved['receipt'] }
    expect(response).to have_http_status(:conflict)
    expect(ticket.reload.lock_version).to eq(0)
  end

  it 'denies an ordinary agent and rejects a ticket belonging to another Account before creating the batch' do
    ticket = sd_ticket(lifecycle_policy_version: source)
    sd_account_user.update!(role: 'agent')
    preview([ticket])
    expect(response).to have_http_status(:forbidden)
    sd_as_admin!
    foreign = create(:jrc_sd_ticket)
    expect { preview([ticket, foreign]) }.not_to change(Audited::Audit, :count)
    expect(response).to have_http_status(:not_found)
    expect(ticket.ticket_events.where(event_type: 'closure_policy_revised').count).to eq(0)
  end

  it 'rejects a destination that changes clocks and keeps the historical SLA obligation' do
    changed = definition.deep_dup
    changed['transitions'].find { |r| r['action'] == 'resolve' }['clocks']['resolution'] = 'keep'
    different = lc_publish(definition: changed, expected_version: 2).current_version
    ticket = sd_ticket(lifecycle_policy_version: source)
    approved = preview([ticket], target_id: different.id)
    expect(approved['tickets'].sole['reason']).to eq('revision_incompatible')
    expect(apply(approved['receipt'])['results'].sole['status']).to eq('blocked')
  end

  it 'revalidates a newly added contractual requirement after application instead of keeping a waiver' do
    service = JrcServiceDesk::Service.create!(account: sd_account, unit: sd_unit, name: 'Serviço operacional', code: 'common', active: true)
    ticket = sd_ticket(lifecycle_policy_version: source, service: service)
    approved = preview([ticket])
    expect(apply(approved['receipt'])['results'].sole['status']).to eq('applied')
    service.update!(approval_required: true)
    get "#{root}/tickets/#{ticket.id}/lifecycle", headers: headers
    expect(response.parsed_body.dig('closure_revision', 'active')).to be(false)
    expect(response.parsed_body['closure_options']).to be_empty
  end
  it 'excludes an incomplete legacy cycle instead of applying only part of the revision' do
    ticket = sd_ticket(lifecycle_policy_version: source)
    snapshot(ticket)
    cycle = ticket.sla_cycles.create!(account: sd_account, unit: sd_unit, lifecycle_policy_version: source,
      sla_snapshot: ticket.reload.latest_sla_snapshot, number: 1, started_at: ticket.opened_at)
    before = ticket.attributes.deep_dup
    approved = preview([ticket])
    expect(approved['tickets'].sole['reason']).to eq('cycle_incompatible')
    expect(apply(approved['receipt'])['results'].sole['status']).to eq('blocked')
    expect(ticket.reload.attributes).to eq(before)
    expect(cycle.sla_clocks.count).to eq(0)
  end

  it 'counts the whole source cohort independently of the selected page' do
    26.times { sd_ticket(lifecycle_policy_version: source) }
    get "#{root}/closure_revisions", headers: headers,
      params: { unit_id: sd_unit.id, source_version_id: source.id, target_version_id: target.id, page: 2 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['total']).to eq(26)
    expect(response.parsed_body['counts']).to eq('eligible' => 26)
    expect(response.parsed_body['items'].size).to eq(1)
  end

  it 'detects a new native note even when the ticket lock version does not change' do
    ticket = sd_ticket(lifecycle_policy_version: source)
    approved = preview([ticket])
    JrcServiceDesk::AddNoteService.new(user_context: sd_context).call(ticket_id: ticket.id,
      attributes: { body: 'Nova nota interna sintética', visibility: 'internal', notification_channels: [] }, idempotency_key: 'after-preview-note')
    expect(apply(approved['receipt'])['results'].sole['status']).to eq('conflict')
    expect(ticket.ticket_events.where(event_type: 'closure_policy_revised').count).to eq(0)
  end

  it 'never reactivates a disabled policy through the simplified revision proposal' do
    lc_publish(definition: definition, enabled: false, expected_version: 2)
    before = JrcServiceDesk::LifecyclePolicyVersion.count
    post "#{root}/closure_revisions/proposal", headers: headers, as: :json,
      params: { unit_id: sd_unit.id, source_version_id: source.id }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcServiceDesk::LifecyclePolicyVersion.count).to eq(before)
    expect(source.lifecycle_policy.reload.enabled?).to be(false)
  end

  context 'with explicitly approved automatic monitoring' do
    let(:old_definition) do
      value = super()
      value['schema_version'] = 2
      value['sla']['escalation_policy'] = { 'enabled' => true, 'automatic' => true,
        'execution_account_user_id' => sd_account_user.id, 'thresholds' => [{ 'percent' => 70, 'queue_id' => nil, 'team_id' => nil }] }
      value['transitions'].each { |rule| rule['clocks']['attendance'] = 'keep' }
      value['pause_reasons'].first['clocks'] = %w[attendance resolution]
      value['reopen']['resume_clocks'] = %w[attendance resolution]
      value
    end

    it 'keeps the original monitored clocks and executor only under the explicitly applied compatible revision' do
      ticket = sd_ticket(lifecycle_policy_version: source)
      snapshot(ticket)
      lc_execute(ticket, 'work_status')
      clock = ticket.sla_cycles.sole.sla_clocks.find_by!(kind: 'attendance')
      expect { JrcServiceDesk::ClockMonitoringBinding.new(clock) }.to raise_error(JrcServiceDesk::IdempotencyConflict)
      approved = preview([ticket])
      expect(apply(approved['receipt'])['results'].sole['status']).to eq('applied')
      expect(JrcServiceDesk::ClockMonitoringBinding.new(clock).automatic?).to be(true)
      travel 50.minutes
      JrcServiceDesk::ClockMonitoringJob.perform_now
      event = ticket.ticket_events.where(event_type: 'clock_threshold_reached').sole
      expect(event.data).to include('clock_id' => clock.id, 'policy_digest' => source.digest)
      expect { JrcServiceDesk::ClockMonitoringJob.perform_now }.not_to change(JrcServiceDesk::TicketEvent, :count)
      # A subsequent publication is not automatically authorized by the earlier batch.
      lc_publish(definition: definition, expected_version: 2)
      expect { JrcServiceDesk::ClockMonitoringBinding.new(clock.reload) }.to raise_error(JrcServiceDesk::IdempotencyConflict)
    end

    it 'still blocks automatic effects when the approved executor loses its operational grant' do
      ticket = sd_ticket(lifecycle_policy_version: source)
      snapshot(ticket)
      lc_execute(ticket, 'work_status')
      approved = preview([ticket])
      apply(approved['receipt'])
      sd_membership.update!(active: false)
      travel 50.minutes
      expect { JrcServiceDesk::ClockMonitoringJob.perform_now }.not_to change(JrcServiceDesk::TicketEvent, :count)
    end
  end

end

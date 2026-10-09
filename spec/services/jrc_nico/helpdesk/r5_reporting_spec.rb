# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcNico::Helpdesk::DailyReporter do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'R5 synthetic reporting company') }
  let(:ticket) { sd_ticket(company_id: company.id) }
  let(:definition) do
    value = JrcNico::Helpdesk::Definition.defaults.merge('unit_ids' => [sd_unit.id], 'company_ids' => [company.id],
                                                         'operator_ids' => [sd_account_user.id])
    value['roles']['thiago'] = [sd_account_user.id]
    value['daily'].merge!('enabled' => true, 'recipients' => [sd_account_user.id], 'channels' => ['nico'])
    value
  end
  let(:policy) do
    JrcNico::Helpdesk::PolicyVersion.create!(account: sd_account, author: sd_account_user, number: 1, state: 'published', enabled: true,
                                             published_at: Time.current, definition: definition,
                                             digest: JrcNico::Helpdesk::Definition.digest(definition))
  end

  before do
    sd_account.update!(custom_attributes: { 'nico_enabled' => true })
    sd_account.enable_features!('jrc_relationship', 'jrc_customer_master')
    sd_as_admin!
  end

  def event(at, key)
    JrcNico::Helpdesk::Event.create!(account: sd_account, actor: sd_account_user, policy_version: policy, ticket: ticket,
                                     rule_key: 'R01', correlation_key: key, detected_at: at)
  end

  it 'uses the real local day and labels previous events separately from todays events' do
    now = Time.utc(2026, 10, 8, 21)
    old = event(Time.utc(2026, 10, 8, 2, 59), 'r5-before-local-midnight')
    current = event(Time.utc(2026, 10, 8, 3, 1), 'r5-after-local-midnight')
    payload = described_class.new(policy, now: now).preview(member: sd_account_user)
    expect(payload['window']).to include('from' => '2026-10-08T03:00:00.000000Z', 'until' => '2026-10-08T21:00:00.000000Z')
    expect(payload['new_event_ids']).to eq([current.id])
    expect(payload['previous_event_ids']).to eq([old.id])
    expect(payload['kpis'][:metrics].map { |row| row[:key] }).to eq(%w[K1 K2 K3 K4 K5 K6 K7])
    expect(JrcNico::Helpdesk::DailyReport.where(account: sd_account)).to be_empty
    expect(JrcNico::Helpdesk::DeliveryReceipt.where(account: sd_account)).to be_empty
  end

  it 'persists one scheduled snapshot and rechecks source permissions before history or terminal receipt reads' do
    ticket
    report = described_class.new(policy, now: Time.utc(2026, 10, 8, 21)).call.fetch(0)
    reader = JrcNico::Helpdesk::ReportHistory.new(sd_account_user)
    expect(reader.find(report.id).fetch('id')).to eq(report.id)
    expect { described_class.new(policy, now: Time.utc(2026, 10, 8, 22)).call }.not_to change(JrcNico::Helpdesk::DailyReport, :count)
    receipt = JrcNico::Helpdesk::DeliveryReceipt.find_by!(source_type: 'daily_report', source_id: report.id, channel: 'nico')
    sd_membership.update!(active: false)
    expect { reader.find(report.id) }.to raise_error(Pundit::NotAuthorizedError)
    expect { JrcNico::Helpdesk::Delivery.new(source: report, recipient: sd_account_user, channel: 'nico').call }
      .to raise_error(Pundit::NotAuthorizedError)
    expect(receipt.reload.state).to eq('delivered')
  end

  it 'denies widening filters and handles skipped local midnight using the first actual local instant' do
    foreign = sd_foreign_unit
    expect { described_class.new(policy, filters: { unit_ids: [foreign.id] }).preview(member: sd_account_user) }
      .to raise_error(Pundit::NotAuthorizedError)
    window = JrcNico::Helpdesk::ReportWindow.new('America/Sao_Paulo', Time.utc(2018, 11, 4, 21))
    expect(window.from).to eq(Time.utc(2018, 11, 4, 3))
    expect(window.date).to eq(Date.new(2018, 11, 4))
  end

  it 'measures zero autonomy only for completely covered actual human closures' do
    lc_publish
    lc_execute(ticket, 'resolve')
    lc_execute(ticket, 'close')
    output = JrcNico::Helpdesk::Kpis.new(member: sd_account_user, policy: policy, from: 1.day.ago).call[:metrics].index_by { |row| row[:key] }
    expect(output['K1']).to include(state: 'available', numerator: 0, denominator: 1, value: 0.0)
    expect(output['K1'][:evidence]['coverage']).to include('covered_human' => 1, 'unknown' => 0, 'autonomous_supported' => 0)
    expect(output['K3'][:evidence]['source_conflict']).to eq('code' => 'C10', 'resolved' => false)
    expect(output['K3'][:evidence]['observations'].pluck('key')).to eq(%w[resolution_sla_overrun_72h age_at_close_72h])
    overrun = output['K3'][:evidence]['observations'].first
    expect(overrun).to include('unknown' => 1, 'value' => nil, 'observation_only' => true)
  end

  [72.hours, 72.hours + 1].each do |overrun_seconds|
    it "observes native calendar overrun #{overrun_seconds}s without choosing the unresolved canonical K3 formula" do
      opened_at = Time.utc(2026, 10, 5, 12)
      clock = nil
      travel_to(opened_at) do
        ticket
        lc_snapshot(ticket)
        lc_publish(definition: lc_definition(tracked: true))
        lc_execute(ticket, 'work_status')
        clock = ticket.reload.sla_cycles.order(number: :desc).first.sla_clocks.find_by!(kind: 'resolution')
      end
      completed_at = clock.due_at + overrun_seconds
      travel_to(completed_at) do
        lc_execute(ticket, 'resolve')
        close = lc_execute(ticket, 'close')
        value = JrcNico::Helpdesk::Kpis.new(member: sd_account_user, policy: policy, from: opened_at,
                                            until_at: completed_at + 1).call[:metrics].find { |metric| metric[:key] == 'K3' }
        expect(value).to include(state: 'sem_dados', numerator: nil, denominator: 1, value: nil,
                                 reason: 'overdue_temporal_basis_not_confirmed')
        expect(value[:evidence]['source_conflict']).to eq('code' => 'C10', 'resolved' => false)
        observations = value[:evidence]['observations'].index_by { |row| row['key'] }
        observed = observations.fetch('resolution_sla_overrun_72h')
        count = overrun_seconds > 72.hours ? 1 : 0
        expect(observed).to include('basis' => 'calendar', 'observation_only' => true, 'unknown' => 0,
                                    'numerator' => count, 'denominator' => 1, 'value' => count * 100.0)
        expect(observed.fetch('samples')).to eq([{ 'closure_id' => close.id, 'cycle_id' => clock.sla_cycle_id,
                                                   'clock_id' => clock.id, 'elapsed_seconds' => overrun_seconds.to_f }])
        expect(observations.fetch('age_at_close_72h')).to include('basis' => 'calendar', 'observation_only' => true,
                                                                  'unknown' => 0, 'numerator' => 1, 'denominator' => 1, 'value' => 100.0)
        expect(clock.reload.achieved_at).to eq(completed_at)
      end
    end
  end

  [Time.utc(2026, 10, 8, 3), Time.utc(2018, 11, 4, 3)].each do |midnight|
    it "keeps the real empty local interval at #{midnight.iso8601} without inventing an earlier cutoff" do
      payload = described_class.new(policy, now: midnight).preview(member: sd_account_user)
      expect(payload['window']['from']).to eq(midnight.iso8601(6))
      expect(payload['window']['until']).to eq(midnight.iso8601(6))
      expect(payload['new_event_ids']).to be_empty
      expect(payload['kpis'][:metrics]).to all(include(state: 'sem_dados', denominator: 0, value: nil))
      expect(JrcNico::Helpdesk::DailyReport.where(account: sd_account)).to be_empty
    end
  end

  it 'returns an empty observed cohort for a currently authorized service with no tickets' do
    service = JrcServiceDesk::Service.create!(account: sd_account, unit: sd_unit, code: 'r5-authorized-empty', name: 'Authorized empty service')
    payload = described_class.new(policy, filters: { service_ids: [service.id] }).preview(member: sd_account_user)
    expect(payload['ticket_ids']).to be_empty
    expect(payload['kpis'][:metrics]).to all(include(state: 'sem_dados', denominator: 0, value: nil))
  end

  it 'keeps historical closure provenance unknown instead of inventing zero autonomy' do
    lc_publish
    lc_execute(ticket, 'resolve')
    close = lc_execute(ticket, 'close')
    # Reconstruct one pre-provenance historical row without updating or disabling append-only history.
    legacy = close.dup
    legacy.request_key = SecureRandom.uuid
    legacy.payload = close.payload.except('origin')
    legacy.save!
    value = JrcNico::Helpdesk::Kpis.new(member: sd_account_user, policy: policy, from: 1.day.ago,
                                        filters: { ticket_ids: [ticket.id] }).call[:metrics].first
    expect(value).to include(state: 'sem_dados', numerator: nil, denominator: 2, value: nil, reason: 'incomplete_native_closure_origin')
    expect(value[:evidence]['coverage']).to include('observed' => 2, 'covered_human' => 1, 'unknown' => 1, 'autonomous_supported' => 0)
  end
end

require 'rails_helper'

RSpec.describe JrcNico::Helpdesk::CycleEvidence do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures

  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'Synthetic cycle company') }
  let(:ticket) { sd_ticket(company_id: company.id) }
  let(:definition) do
    value = JrcNico::Helpdesk::Definition.defaults.merge('unit_ids' => [sd_unit.id], 'company_ids' => [company.id],
                                                         'operator_ids' => [sd_account_user.id])
    value['rules']['R14']['enabled'] = true
    value
  end
  let(:policy) do
    JrcNico::Helpdesk::PolicyVersion.create!(account: sd_account, author: sd_account_user, number: 1, state: 'published', enabled: true,
                                             published_at: Time.current, definition: definition,
                                             digest: JrcNico::Helpdesk::Definition.digest(definition))
  end
  let(:context) { JrcNico::Helpdesk::Context.new(sd_account_user) }
  let(:writer) { JrcNico::Helpdesk::ProfileWriter.new(sd_account_user) }
  let(:approvals) { JrcNico::Helpdesk::Approvals.new(sd_account_user) }

  before do
    sd_account.update!(custom_attributes: { 'nico_enabled' => true })
    sd_as_admin!
    lc_publish
    lc_execute(ticket, 'resolve')
    lc_execute(ticket, 'close')
  end

  def facts_for(value = ticket)
    JrcNico::Helpdesk::Facts.new(context: context, policy: policy, ticket: value.reload, trigger: 'customer_return').call
  end

  def capture_return
    policy
    JrcNico::Helpdesk::Capture.call(ticket: ticket, trigger: 'customer_return', origin_key: 'synthetic-negative-return',
                                    member: sd_account_user).first
  end

  def reopen_arguments
    ticket.reload
    { 'ticket_id' => ticket.id, 'rule_key' => 'reopen', 'expected_lock_version' => ticket.lock_version,
      'expected_policy_version_id' => ticket.lifecycle_policy_version_id }
  end

  it 'does not reuse a legacy negative boolean without native cycle, actor and time evidence' do
    JrcNico::Helpdesk::TicketProfile.create!(account: sd_account, unit: sd_unit, company: company, ticket: ticket,
                                             evidence: { 'negative_return' => true })
    expect(facts_for['negative_return']).to be(false)
    expect(capture_return).to be_nil
  end

  it 'records a server-owned attestation and deduplicates repeat capture and repeat attestation' do
    profile = writer.call(ticket_id: ticket.id, attributes: { 'negative_return' => true })
    expect(profile.evidence).to include('negative_return_cycle_key' => described_class.key(ticket),
                                        'negative_return_attested_by' => sd_account_user.id)
    first = capture_return
    expect(first.evidence['negative_return_at']).to eq(profile.evidence['negative_return_at'])
    travel 1.second do
      replay = writer.call(ticket_id: ticket.id, attributes: { 'negative_return' => true })
      expect(replay.evidence['negative_return_at']).to eq(profile.evidence['negative_return_at'])
      expect(capture_return.id).to eq(first.id)
    end
    expect(JrcNico::Helpdesk::Event.where(ticket: ticket, rule_key: 'R14').count).to eq(1)
  end

  it 'executes the approved native reopen once on the same ticket without creating another ticket' do
    writer.call(ticket_id: ticket.id, attributes: { 'negative_return' => true })
    event = capture_return
    approval = approvals.prepare(event_id: event.id, tool: 'transition_service_ticket', arguments: reopen_arguments)
    expect { approvals.approve(id: approval.id, payload_digest: approval.payload_digest) }.not_to change(JrcServiceDesk::Ticket, :count)
    expect(approval.reload.state).to eq('succeeded')
    expect(ticket.reload.status.phase).to eq('open')
    expect(facts_for['negative_return']).to be(false)
    expect { approvals.approve(id: approval.id, payload_digest: approval.payload_digest) }
      .not_to(change { ticket.lifecycle_transitions.where(action: 'reopen').count })
  end

  it 'invalidates a prepared approval after a reopen and new close and requires a new attestation and review' do
    writer.call(ticket_id: ticket.id, attributes: { 'negative_return' => true })
    first = capture_return
    approval = approvals.prepare(event_id: first.id, tool: 'transition_service_ticket', arguments: reopen_arguments)
    travel 1.second do
      lc_execute(ticket, 'reopen')
      lc_execute(ticket, 'resolve')
      lc_execute(ticket, 'close')
      expect(facts_for['negative_return']).to be(false)
      expect { approvals.approve(id: approval.id, payload_digest: approval.payload_digest) }.to raise_error(ArgumentError, /current ticket cycle/)
      writer.call(ticket_id: ticket.id, attributes: { 'negative_return' => true })
      second = capture_return
      expect(second.id).not_to eq(first.id)
      expect(second.evidence['cycle_key']).not_to eq(first.evidence['cycle_key'])
      expect { approvals.approve(id: approval.id, payload_digest: approval.payload_digest) }.to raise_error(ArgumentError, /attestation changed/)
      expect(ticket.reload.status.phase).to eq('closed')
    end
  end

  it 'rejects attestation times preceding closure, future times and a foreign account actor' do
    profile = writer.call(ticket_id: ticket.id, attributes: { 'negative_return' => true })
    base = profile.evidence.deep_dup
    closed_at = ticket.lifecycle_transitions.where(action: 'close').maximum(:occurred_at)
    [1.second.before(closed_at), 1.second.from_now].each do |at|
      profile.update!(evidence: base.merge('negative_return_at' => at.iso8601(6)))
      expect(facts_for['negative_return']).to be(false)
    end
    foreign = create(:account_user, account: sd_foreign_account)
    profile.update!(evidence: base.merge('negative_return_attested_by' => foreign.id))
    expect(facts_for['negative_return']).to be(false)
  end

  it 'requires an actual pending approval on the same waiting ticket and an attestation after that request' do
    waiting = sd_ticket(company_id: company.id)
    lc_execute(waiting, 'pause', reason_code: 'customer')
    writer.call(ticket_id: waiting.id, attributes: { 'negative_return' => true })
    expect(facts_for(waiting)['negative_return']).to be(false)
    travel 1.second do
      JrcServiceDesk::CreateApprovalService.new(user_context: sd_context).call(ticket_id: waiting.id,
                                                                               attributes: {
                                                                                 title: 'Synthetic customer approval',
                                                                                 due_at: 1.day.from_now.iso8601,
                                                                                 approver_account_user_id: sd_account_user.id
                                                                               },
                                                                               idempotency_key: SecureRandom.uuid)
      expect(facts_for(waiting)['negative_return']).to be(false)
      writer.call(ticket_id: waiting.id, attributes: { 'negative_return' => true })
      facts = facts_for(waiting)
      expect(facts['negative_return']).to be(true)
      expect(JrcNico::Helpdesk::RuleDetector.new(definition: definition, facts: facts).call.pluck(:rule_key)).to eq(['R14'])
    end
    expect(facts_for['negative_return']).to be(false)
  end

  it 'blocks a pending review if its negative attestation is withdrawn' do
    writer.call(ticket_id: ticket.id, attributes: { 'negative_return' => true })
    approval = approvals.prepare(event_id: capture_return.id, tool: 'transition_service_ticket', arguments: reopen_arguments)
    writer.call(ticket_id: ticket.id, attributes: { 'negative_return' => false })
    expect { approvals.approve(id: approval.id, payload_digest: approval.payload_digest) }.to raise_error(ArgumentError)
    expect(ticket.reload.status.phase).to eq('closed')
  end
end

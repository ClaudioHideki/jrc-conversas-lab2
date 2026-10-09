require 'rails_helper'

RSpec.describe JrcNico::Helpdesk::Controls do
  include_context 'JRC Service Desk domain'
  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'Synthetic pilot company') }
  let(:ticket) { sd_ticket(company_id: company.id) }
  let(:definition) do
    value = JrcNico::Helpdesk::Definition.defaults.merge('unit_ids' => [sd_unit.id], 'company_ids' => [company.id],
                                                         'operator_ids' => [sd_account_user.id])
    value['rules']['R01']['enabled'] = true
    value
  end
  let(:policy) do
    JrcNico::Helpdesk::PolicyVersion.create!(account: sd_account, author: sd_account_user, number: 1, state: 'published', enabled: true,
                                             published_at: Time.current, definition: definition,
                                             digest: JrcNico::Helpdesk::Definition.digest(definition))
  end
  let(:event) do
    JrcNico::Helpdesk::Event.create!(account: sd_account, actor: sd_account_user, policy_version: policy, ticket: ticket, rule_key: 'R01',
                                     correlation_key: 'synthetic-halt-event', detected_at: Time.current)
  end

  before do
    sd_account.update!(custom_attributes: { 'nico_enabled' => true })
    sd_as_admin!
  end

  it 'halts operational execution without modifying the immutable published digest and writes one audit per request' do
    digest = policy.digest
    service = described_class.new(sd_account_user)
    first = service.disable(id: policy.id, reason: 'Synthetic pilot stop', request_key: 'synthetic-halt')
    expect(policy.reload.enabled?).to be(false)
    expect(policy.digest).to eq(digest)
    expect(service.disable(id: policy.id, reason: 'Synthetic pilot stop', request_key: 'synthetic-halt')).to eq(first)
    expect(JrcNico::Helpdesk::ControlEvent.where(policy_version: policy).count).to eq(1)
    expect { first.update!(reason: 'Changed history') }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'blocks a queued event and preparation after the kill-switch was used' do
    event
    described_class.new(sd_account_user).disable(id: policy.id, reason: 'Synthetic pilot stop', request_key: 'synthetic-halt')
    expect(JrcNico::Helpdesk::EventProcessor.new(event).call).to have_attributes(state: 'blocked', reason: 'policy_disabled_or_scope_revoked')
    expect do
      JrcNico::Helpdesk::Approvals.new(sd_account_user).prepare(event_id: event.id, tool: 'add_service_ticket_note',
                                                                arguments: { 'ticket_id' => ticket.id, 'body' => 'Synthetic blocked note' })
    end.to raise_error(Pundit::NotAuthorizedError)
    expect(ticket.ticket_notes).to be_empty
  end

  it 'blocks approval and native I/O if the policy was halted after the preview' do
    approval = JrcNico::Helpdesk::Approvals.new(sd_account_user).prepare(event_id: event.id, tool: 'add_service_ticket_note',
                                                                         arguments: { 'ticket_id' => ticket.id, 'body' => 'Synthetic pending note' })
    described_class.new(sd_account_user).disable(id: policy.id, reason: 'Synthetic pilot stop', request_key: 'synthetic-halt')
    expect { JrcNico::Helpdesk::Approvals.new(sd_account_user).approve(id: approval.id, payload_digest: approval.payload_digest) }
      .to raise_error(Pundit::NotAuthorizedError)
    expect(ticket.ticket_notes).to be_empty
    expect(JrcNico::Helpdesk::Capture.call(ticket: ticket, trigger: 'monitor', origin_key: 'synthetic-monitor', member: sd_account_user)).to be_empty
  end

  it 'rejects foreign policy IDs, changed audit requests and missing Unit grants' do
    service = described_class.new(sd_account_user)
    expect { service.disable(id: 9_999_999, reason: 'Synthetic stop', request_key: 'synthetic-halt') }.to raise_error(ActiveRecord::RecordNotFound)
    service.disable(id: policy.id, reason: 'Synthetic stop', request_key: 'synthetic-halt')
    expect { service.disable(id: policy.id, reason: 'Different reason', request_key: 'synthetic-halt') }.to raise_error(ArgumentError)
    sd_membership.update!(active: false)
    expect { service.disable(id: policy.id, reason: 'Synthetic stop', request_key: 'another-halt') }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rechecks a revoked administrator after the service was constructed' do
    service = described_class.new(sd_account_user)
    policy
    sd_account_user.update!(role: :agent)
    expect { service.disable(id: policy.id, reason: 'Synthetic stop', request_key: 'revoked-actor') }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcNico::Helpdesk::ControlEvent.where(policy_version: policy)).to be_empty
    expect(policy.reload.enabled?).to be(true)
  end
end

# frozen_string_literal: true

# Native records and Capture only; no source builder, authorization or delivery is mocked.
RSpec.shared_context 'NICO HelpDesk native event email' do
  include_context 'JRC Service Desk domain'

  let(:email_rule) { 'R10' }
  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'Synthetic event email customer') }
  let(:ticket) { sd_ticket(company_id: company.id) }
  let(:email_recipient) { sd_account_user }
  let(:definition) do
    value = JrcNico::Helpdesk::Definition.defaults.merge(
      'unit_ids' => [sd_unit.id], 'company_ids' => [company.id], 'operator_ids' => [sd_account_user.id]
    )
    value['roles']['thiago'] = [email_recipient.id]
    value['rules'][email_rule].merge!('enabled' => true, 'recipients' => [email_recipient.id], 'channels' => ['email'])
    value
  end
  let(:policy) do
    JrcNico::Helpdesk::PolicyVersion.create!(
      account: sd_account, author: sd_account_user, number: 1, state: 'published', enabled: true,
      published_at: Time.current, definition: definition, digest: JrcNico::Helpdesk::Definition.digest(definition)
    )
  end
  let(:event) do
    text = email_rule == 'R11' ? 'Advogado: notificação extrajudicial PRIVATE-EVENT-EVIDENCE.' : 'Reclamação: PRIVATE-EVENT-EVIDENCE.'
    note = JrcServiceDesk::AddNoteService.new(user_context: sd_context).call(
      ticket_id: ticket.id, attributes: { body: text }, idempotency_key: SecureRandom.uuid
    )
    JrcNico::Helpdesk::ProfileWriter.new(sd_account_user).call(ticket_id: ticket.id, attributes: { customer_note_ids: [note.id] })
    policy
    values = JrcNico::Helpdesk::Capture.new(sd_account_user).call(
      ticket: ticket.reload, trigger: 'monitor', origin_key: "native-email:#{ticket.id}"
    )
    expect(values.pluck(:rule_key)).to eq([email_rule])
    values.fetch(0)
  end
  let(:receipt) do
    JrcNico::Helpdesk::DeliveryReceipt.create!(account: sd_account, recipient: email_recipient,
                                               source_type: 'event', source_id: event.id, channel: 'email')
  end

  before do
    sd_account.update!(custom_attributes: { 'nico_enabled' => true })
    sd_as_admin!
    receipt
  end

  def process_event_email
    JrcNico::Helpdesk::EventJob.perform_now(event.id)
    receipt.reload
  end
end

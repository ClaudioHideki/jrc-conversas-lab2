# frozen_string_literal: true

require 'rails_helper'
require 'timeout'
require 'stringio'

# Every fixture and claim is committed; only the explicitly named disposable database and Mail::TestMailer may be used.
RSpec.describe JrcNico::Helpdesk::EmailDelivery, :sd_concurrency do
  self.use_transactional_tests = false
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskConcurrency
  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'Committed report source fixture') }
  let(:source_ticket) { sd_ticket(company_id: company.id) }
  let(:report_payload) { { 'ticket_ids' => [source_ticket.id], 'visible_event_ids' => [] } }

  let(:definition) do
    value = JrcNico::Helpdesk::Definition.defaults.merge('unit_ids' => [sd_unit.id], 'company_ids' => [company.id],
                                                         'operator_ids' => [sd_account_user.id])
    value['roles']['thiago'] = [sd_account_user.id]
    value['daily'].merge!('enabled' => true, 'recipients' => [sd_account_user.id], 'channels' => ['email'])
    value
  end
  let(:policy) do
    JrcNico::Helpdesk::PolicyVersion.create!(account: sd_account, author: sd_account_user, number: 1, state: 'published', enabled: true,
                                             published_at: Time.current, definition: definition,
                                             digest: JrcNico::Helpdesk::Definition.digest(definition))
  end
  let(:report) do
    JrcNico::Helpdesk::DailyReport.create!(account: sd_account, recipient: sd_account_user, policy_version: policy,
                                           report_date: Date.current, scope_digest: SecureRandom.hex(32), timezone: 'UTC', cutoff_at: Time.current,
                                           payload: report_payload)
  end
  let(:receipt) do
    JrcNico::Helpdesk::DeliveryReceipt.create!(account: sd_account, recipient: sd_account_user,
                                               source_type: 'daily_report', source_id: report.id, channel: 'email')
  end

  around do |example|
    db = ENV.fetch('POSTGRES_DATABASE', nil)
    allowed = Rails.env.test? && ENV['JRC_SD_CONCURRENCY'] == '1' && db == 'jrc_rel_sd_r345_concurrency_test' &&
              ActiveRecord::Base.connection.adapter_name == 'PostgreSQL' &&
              ActiveRecord::Base.connection.select_value('SELECT current_database()') == db
    if allowed
      with_test_mailer { example.run }
    else
      skip 'Only the explicitly named R345 disposable PostgreSQL database may exercise committed mail claims'
    end
  end

  before do
    sd_account.update!(custom_attributes: { 'nico_enabled' => true })
    sd_as_admin!
    receipt
    raise 'Committed mail validation must not run inside an outer transaction' if ActiveRecord::Base.connection.transaction_open?
    raise 'Committed mail validation permits only the native test transport' unless JrcNicoHelpdeskMailer.delivery_method == :test
  end

  it 'uses a committed isolated fixture and native test transport without requesting outbound delivery' do
    expect(ActiveRecord::Base.connection.transaction_open?).to be(false)
    expect(JrcNicoHelpdeskMailer.delivery_method).to eq(:test)
    expect(receipt.reload).to have_attributes(state: 'pending', attempt_number: 0, claim_token: nil)
    expect(delivered_messages).to be_empty
  end

  def with_test_mailer
    previous = [JrcNicoHelpdeskMailer.delivery_method, JrcNicoHelpdeskMailer.perform_deliveries, ENV.fetch('FRONTEND_URL', nil)]
    JrcNicoHelpdeskMailer.delivery_method = :test
    JrcNicoHelpdeskMailer.perform_deliveries = true
    ENV['FRONTEND_URL'] = 'https://r345-mail.example.test'
    yield
  ensure
    JrcNicoHelpdeskMailer.delivery_method, JrcNicoHelpdeskMailer.perform_deliveries = previous.first(2)
    previous.last ? ENV['FRONTEND_URL'] = previous.last : ENV.delete('FRONTEND_URL')
  end

  def delivered_messages
    ActionMailer::Base.deliveries.select { |mail| mail.body.decoded.strip == JrcNico::Helpdesk::EmailPointer.url(report) }
  end

  def claim_from_other_connection(id)
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        row = JrcNico::Helpdesk::DeliveryReceipt.find(id)
        [connection.object_id, row.state, row.attempt_number, row.claim_token, connection.transaction_open?]
      end
    end
    Timeout.timeout(10) { worker.value }
  ensure
    worker&.kill if worker&.alive?
    worker&.join
  end

  def committed_claim_from_other_connection(id)
    current = ActiveRecord::Base.connection.object_id
    observed = claim_from_other_connection(id)
    expect(observed).to include('dispatching', 1)
    expect(observed.first).not_to eq(current)
    expect(observed[3]).to be_present
    expect(observed.last).to be(false)
  end

  # Wrap only the real adapter constructed for this message; native transport, claim and COMMIT still run.
  def intercept_native_transport(&)
    allow(JrcNico::Helpdesk::EmailTransport).to receive(:new).and_wrap_original do |constructor, *args|
      constructor.call(*args).tap do |transport|
        allow(transport).to receive(:deliver_mail).and_wrap_original(&)
      end
    end
  end

  it 'exposes a committed claim on a second connection before native test transport and distinguishes acceptance from delivery' do
    id = receipt.id
    intercept_native_transport do |method, mail, &block|
      committed_claim_from_other_connection(id)
      expect(mail.delivery_method).to be_a(Mail::TestMailer)
      method.call(mail, &block)
    end
    expect(described_class.new(receipt).call).to have_attributes(state: 'sent', attempt_number: 1, delivered_at: nil)
    expect(receipt.reload.sent_at).to be_present
    expect(receipt.evidence).to eq('adapter' => 'action_mailer', 'outcome' => 'accepted')
    expect(delivered_messages.size).to eq(1)
    expect(delivered_messages.first.to).to eq([sd_user.email])
    expect(delivered_messages.first.body.decoded.strip).to eq(JrcNico::Helpdesk::EmailPointer.url(report))
  end

  it 'serializes simultaneous retries into one claim and one native transport acceptance' do
    id = receipt.id
    outcomes = concurrently(Array.new(2) do
      -> { described_class.new(JrcNico::Helpdesk::DeliveryReceipt.find(id)).call.state }
    end)
    expect(outcomes).to all(be_in(%w[dispatching sent]))
    expect(receipt.reload).to have_attributes(state: 'sent', attempt_number: 1)
    expect(delivered_messages.size).to eq(1)
    described_class.new(receipt).call
    expect(delivered_messages.size).to eq(1)
  end

  it 'records uncertainty without leaking a transport error or automatically sending again' do
    marker = 'sensitive-smtp-marker-do-not-log'
    output = StringIO.new
    logger = ActiveSupport::Logger.new(output)
    allow(Rails).to receive(:logger).and_return(logger)
    intercept_native_transport do |method, mail, &block|
      allow(mail.delivery_method).to receive(:deliver!).and_raise(Net::SMTPAuthenticationError, marker)
      method.call(mail, &block)
    end
    expect(described_class.new(receipt).call).to have_attributes(state: 'unknown', reason: 'mail_transport_uncertain', attempt_number: 1)
    expect(delivered_messages).to be_empty
    expect(output.string).not_to include(marker, sd_user.email)
    expect { described_class.new(receipt).call }.not_to(change { receipt.reload.attempt_number })
    expect(delivered_messages).to be_empty
  end

  it 'does not re-send an interrupted committed claim' do
    claim = JrcNico::Helpdesk::EmailClaim.new(receipt).fingerprints
    receipt.update!(claim.merge(state: 'dispatching', claim_token: SecureRandom.uuid, attempt_number: 1,
                                attempted_at: Time.current, dispatching_at: Time.current))
    expect(described_class.new(receipt).call.state).to eq('dispatching')
    expect(delivered_messages).to be_empty
    expect(receipt.reload.attempt_number).to eq(1)
  end

  it 'rechecks current activation before returning an accepted receipt without altering confirmed evidence' do
    described_class.new(receipt).call
    before = receipt.reload.attributes
    JrcNico::Helpdesk::PolicyControl.create!(account: sd_account, policy_version: policy, halted: true, halted_at: Time.current)
    expect { described_class.new(receipt).call }.to raise_error(Pundit::NotAuthorizedError)
    expect(receipt.reload.attributes).to eq(before)
    expect(delivered_messages.size).to eq(1)
  end

  it 'blocks an unconfirmed destination without claiming or attempting the transport' do
    sd_user.update!(confirmed_at: nil)
    expect(described_class.new(receipt).call).to have_attributes(state: 'blocked', attempt_number: 0, claim_token: nil)
    expect(delivered_messages).to be_empty
  end

  it 'rechecks destination identity after the committed claim and before the native adapter' do
    intercept_native_transport do |method, mail, &block|
      sd_user.update!(confirmed_at: nil)
      method.call(mail, &block)
    end
    expect(described_class.new(receipt).call).to have_attributes(state: 'blocked', reason: 'delivery_authorization_revoked', attempt_number: 1)
    expect(delivered_messages).to be_empty
  end

  it 'rejects a pointer origin with credentials and preserves the blocked receipt' do
    ENV['FRONTEND_URL'] = 'https://disallowed:secret@r345-mail.example.test'
    expect(described_class.new(receipt).call).to have_attributes(state: 'blocked', attempt_number: 0, claim_token: nil)
    expect(ActionMailer::Base.deliveries.select { |mail| mail.to == [sd_user.email] }).to be_empty
  end

  it 'revalidates the real source unit before attempting a claim' do
    sd_membership.update!(active: false)
    expect(described_class.new(receipt).call).to have_attributes(state: 'blocked', attempt_number: 0, claim_token: nil)
    expect(delivered_messages).to be_empty
  end

  it 'revalidates the real source unit after claim commit and before I/O' do
    intercept_native_transport do |method, mail, &block|
      sd_membership.update!(active: false)
      method.call(mail, &block)
    end
    expect(described_class.new(receipt).call).to have_attributes(state: 'blocked', reason: 'delivery_authorization_revoked', attempt_number: 1)
    expect(delivered_messages).to be_empty
  end

  it 'rechecks NICO account activation after claim commit without changing the account provider' do
    intercept_native_transport do |method, mail, &block|
      sd_account.update!(custom_attributes: { 'nico_enabled' => false })
      method.call(mail, &block)
    end
    expect(described_class.new(receipt).call).to have_attributes(state: 'blocked', reason: 'delivery_authorization_revoked')
    expect(delivered_messages).to be_empty
  end

  it 'rejects destination drift instead of sending the claimed report to the newly configured address' do
    changed_email = "changed-r345-recipient-#{sd_user.id}@example.test"
    intercept_native_transport do |method, mail, &block|
      sd_user.skip_reconfirmation!
      sd_user.update!(email: changed_email)
      expect(sd_user.reload.email).to eq(changed_email)
      method.call(mail, &block)
    end
    expect(described_class.new(receipt).call).to have_attributes(state: 'blocked', reason: 'delivery_authorization_revoked')
    expect(delivered_messages).to be_empty
  end

  { body: 'tampered-private-report-body', cc: ['other-r345-recipient@example.test'],
    to: ['other-r345-recipient@example.test'] }.each do |field, value|
    it "blocks an interceptor changing #{field} rather than accepting an altered authorized message" do
      intercept_native_transport do |method, mail, &block|
        mail.public_send("#{field}=", value)
        method.call(mail, &block)
      end
      expect(described_class.new(receipt).call).to have_attributes(state: 'blocked', reason: 'delivery_authorization_revoked')
      expect(delivered_messages).to be_empty
    end
  end

  it 'does not label a disabled delivery adapter as accepted or delivered' do
    JrcNicoHelpdeskMailer.perform_deliveries = false
    expect(described_class.new(receipt).call).to have_attributes(state: 'blocked', reason: 'delivery_authorization_revoked', sent_at: nil)
    expect(receipt.delivered_at).to be_nil
    expect(delivered_messages).to be_empty
  end

  it 'does not automatically retry a known failed receipt or mutate its identity' do
    receipt.update!(state: 'failed', reason: 'historical-known-failure')
    expect(described_class.new(receipt).call.state).to eq('failed')
    expect(delivered_messages).to be_empty
    expect { receipt.update!(source_id: report.id + 1) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(receipt.reload.source_id).to eq(report.id)
  end

  it 'sends only the authenticated report pointer and suppresses raw ActionMailer delivery instrumentation' do
    observed = []
    subscriber = ActiveSupport::Notifications.subscribe('deliver.action_mailer') { |*args| observed << args.last }
    described_class.new(receipt).call
    expect(receipt.reload.state).to eq('sent')
    expect(delivered_messages.first.body.decoded.strip).to eq(
      "https://r345-mail.example.test/app/accounts/#{sd_account.id}/nico-helpdesk?report_id=#{report.id}"
    )
    expect(delivered_messages.first.attachments).to be_empty
    expect(observed).to be_empty
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  context 'with protected details in the persisted report payload' do
    let(:report_payload) { super().merge('internal_customer_evidence' => 'PRIVATE-R345-REPORT-EVIDENCE') }

    it 'keeps the full snapshot behind authenticated current authorization rather than placing it in the external body' do
      described_class.new(receipt).call
      expect(receipt.reload.state).to eq('sent')
      expect(delivered_messages.first.body.decoded).not_to include('PRIVATE-R345-REPORT-EVIDENCE')
      expect(delivered_messages.first.body.decoded.strip).to eq(JrcNico::Helpdesk::EmailPointer.url(report))
    end
  end
end

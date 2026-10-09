# frozen_string_literal: true

require 'rails_helper'
require 'stringio'

# Real committed PostgreSQL claims and Mail::TestMailer only; no SMTP/provider is exercised.
RSpec.describe JrcNico::Helpdesk::EmailDelivery, :sd_concurrency do
  self.use_transactional_tests = false
  include_context 'NICO HelpDesk native event email'
  include JrcServiceDeskConcurrency

  let(:recipient_user) { create(:user) }
  let(:email_recipient) { create(:account_user, account: sd_account, user: recipient_user, role: :administrator) }
  let(:recipient_membership) { create(:jrc_sd_membership, unit: sd_unit, account_user: email_recipient) }

  around do |example|
    db = ENV.fetch('POSTGRES_DATABASE', nil)
    allowed = Rails.env.test? && ENV['JRC_SD_CONCURRENCY'] == '1' && db == 'jrc_rel_sd_r345_concurrency_test' &&
              ActiveRecord::Base.connection.adapter_name == 'PostgreSQL' &&
              ActiveRecord::Base.connection.select_value('SELECT current_database()') == db
    if allowed
      with_event_test_mailer { example.run }
    else
      skip 'Only the explicitly named R345 disposable PostgreSQL database may exercise committed event mail claims'
    end
  end

  before do
    recipient_membership
    raise 'Event mail claim must be committed' if ActiveRecord::Base.connection.transaction_open?
    raise 'Event mail validation permits only native test transport' unless JrcNicoHelpdeskMailer.delivery_method == :test
  end

  def with_event_test_mailer
    previous = [JrcNicoHelpdeskMailer.delivery_method, JrcNicoHelpdeskMailer.perform_deliveries, ENV.fetch('FRONTEND_URL', nil)]
    JrcNicoHelpdeskMailer.delivery_method = :test
    JrcNicoHelpdeskMailer.perform_deliveries = true
    ENV['FRONTEND_URL'] = 'https://r345-mail.example.test'
    yield
  ensure
    JrcNicoHelpdeskMailer.delivery_method, JrcNicoHelpdeskMailer.perform_deliveries = previous.first(2)
    previous.last ? ENV['FRONTEND_URL'] = previous.last : ENV.delete('FRONTEND_URL')
  end

  def event_messages
    ActionMailer::Base.deliveries.select { |mail| mail.to == [recipient_user.email] }
  end

  def intercept_event_transport(&)
    allow(JrcNico::Helpdesk::EmailTransport).to receive(:new).and_wrap_original do |constructor, *args|
      constructor.call(*args).tap { |transport| allow(transport).to receive(:deliver_mail).and_wrap_original(&) }
    end
  end

  def verify_event_committed_claim(id)
    current = ActiveRecord::Base.connection.object_id
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        row = JrcNico::Helpdesk::DeliveryReceipt.find(id)
        [connection.object_id, row.state, row.claim_token, row.attempt_number, connection.transaction_open?]
      end
    end
    observed = Timeout.timeout(10) { worker.value }
    expect(observed.first).not_to eq(current)
    expect(observed[1..]).to match(['dispatching', be_present, 1, false])
  ensure
    worker&.kill if worker&.alive?
    worker&.join
  end

  it 'delivers the real Capture → EventJob → durable claim chain as an authenticated pointer only' do
    id = receipt.id
    intercept_event_transport do |method, mail, &block|
      verify_event_committed_claim(id)
      expect(mail.delivery_method).to be_a(Mail::TestMailer)
      method.call(mail, &block)
    end
    expect(event.reload.state).to eq('detected')
    expect(process_event_email).to have_attributes(state: 'sent', attempt_number: 1, delivered_at: nil)
    expect(event.reload).to have_attributes(state: 'prepared', reason: 'approval_required', actor_id: sd_account_user.id)
    expect(event_messages.size).to eq(1)
    message = event_messages.fetch(0)
    expect(message.body.decoded.strip).to eq("https://r345-mail.example.test/app/accounts/#{sd_account.id}/nico-helpdesk")
    expect(message.subject).to eq(I18n.t('jrc_nico.helpdesk.event_mailer_subject', locale: :en))
    expect(message.subject).not_to eq(I18n.t('jrc_nico.helpdesk.mailer_subject', locale: :en))
    expect(message.body.decoded).not_to include('PRIVATE-EVENT-EVIDENCE', 'matched_terms', ticket.title)
    expect(message.attachments).to be_empty
    expect(receipt.reload.evidence).to eq('adapter' => 'action_mailer', 'outcome' => 'accepted')
    expect(receipt.sent_at).to be_present
  end

  it 'serializes concurrent native EventJob retries into exactly one claim and one acceptance' do
    id = event.id
    outcomes = concurrently(Array.new(2) { -> { JrcNico::Helpdesk::EventJob.perform_now(id); receipt.reload.state } })
    expect(outcomes).to all(be_in(%w[dispatching sent]))
    expect(receipt.reload).to have_attributes(state: 'sent', attempt_number: 1)
    expect(event_messages.size).to eq(1)
    process_event_email
    expect(event_messages.size).to eq(1)
  end

  it 'keeps an uncertain event acceptance terminal without logging transport details or raw evidence' do
    marker = 'PRIVATE-SMTP-ERROR-MARKER'
    output = StringIO.new
    allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(output))
    intercept_event_transport do |method, mail, &block|
      allow(mail.delivery_method).to receive(:deliver!).and_raise(Net::SMTPAuthenticationError, marker)
      method.call(mail, &block)
    end
    expect(process_event_email).to have_attributes(state: 'unknown', reason: 'mail_transport_uncertain', attempt_number: 1)
    expect(event_messages).to be_empty
    expect(output.string).not_to include(marker, recipient_user.email, 'PRIVATE-EVENT-EVIDENCE')
    expect { process_event_email }.not_to(change { receipt.reload.attempt_number })
    expect(event_messages).to be_empty
  end

  it 'rechecks native OFF control before preparing or attempting an email' do
    JrcNico::Helpdesk::Controls.new(sd_account_user).disable(id: policy.id, reason: 'Synthetic stop', request_key: SecureRandom.uuid)
    process_event_email
    expect(event.reload).to have_attributes(state: 'blocked', reason: 'policy_disabled_or_scope_revoked')
    expect(receipt.reload).to have_attributes(state: 'pending', attempt_number: 0, claim_token: nil)
    expect(event_messages).to be_empty
  end

  it 'rejects an unconfirmed current recipient without acquiring a delivery claim' do
    recipient_user.update!(confirmed_at: nil)
    expect(process_event_email).to have_attributes(state: 'blocked', reason: 'verified_event_recipient_and_origin_required', attempt_number: 0)
    expect(event_messages).to be_empty
  end

  it 'rejects a recipient who lost current Unit membership even if designated in the immutable rule' do
    recipient_membership.update!(active: false)
    create(:jrc_sd_membership, unit: sd_other_unit, account_user: email_recipient)
    expect(process_event_email).to have_attributes(state: 'blocked', reason: 'recipient_permission_revoked', attempt_number: 0)
    expect(event_messages).to be_empty
  end

  it 'rejects native operator-role revocation after durable claim and before the transport' do
    intercept_event_transport do |method, mail, &block|
      role = create(:custom_role, account: sd_account, permissions: ['jrc_service_desk_module_view'])
      sd_account_user.update!(custom_role: role)
      method.call(mail, &block)
    end
    expect(process_event_email).to have_attributes(state: 'blocked', reason: 'delivery_authorization_revoked', attempt_number: 1)
    expect(event_messages).to be_empty
  end

  it 'rejects current native destination-role revocation after claim and before I/O' do
    intercept_event_transport do |method, mail, &block|
      role = create(:custom_role, account: sd_account, permissions: ['jrc_service_desk_module_view'])
      email_recipient.update!(custom_role: role)
      method.call(mail, &block)
    end
    expect(process_event_email).to have_attributes(state: 'blocked', reason: 'delivery_authorization_revoked', attempt_number: 1)
    expect(event_messages).to be_empty
  end

  it 'rejects a changed published policy digest before acquiring a claim' do
    policy.update_columns(digest: '0' * 64)
    expect(process_event_email).to have_attributes(state: 'blocked', attempt_number: 0, claim_token: nil)
    expect(event_messages).to be_empty
  end

  it 'rejects tampered immutable event evidence against the committed payload fingerprint' do
    intercept_event_transport do |method, mail, &block|
      event.update_columns(evidence: event.evidence.merge('tampered_payload' => 'PRIVATE-EVENT-EVIDENCE'))
      method.call(mail, &block)
    end
    expect(process_event_email).to have_attributes(state: 'blocked', reason: 'delivery_authorization_revoked', attempt_number: 1)
    expect(event_messages).to be_empty
  end

  it 'rechecks original pilot customer identity drift after claim rather than broadening the cohort' do
    intercept_event_transport do |method, mail, &block|
      other = JrcCustomers::Company.create!(account: sd_account, name: 'Outside the explicitly approved email pilot')
      ticket.update!(company_id: other.id)
      method.call(mail, &block)
    end
    expect(process_event_email).to have_attributes(state: 'blocked', reason: 'delivery_authorization_revoked', attempt_number: 1)
    expect(event_messages).to be_empty
  end

  it 'rejects a foreign Account destination without inserting a receipt' do
    foreign = create(:account_user, account: sd_foreign_account)
    expect do
      JrcNico::Helpdesk::Delivery.new(source: event, recipient: foreign, channel: 'email').call
    end.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcNico::Helpdesk::DeliveryReceipt.where(recipient: foreign, source_type: 'event', source_id: event.id)).to be_empty
    expect(event_messages).to be_empty
  end

  it 'does not expose raw native ActionMailer delivery instrumentation for an immediate alert' do
    observed = []
    subscriber = ActiveSupport::Notifications.subscribe('deliver.action_mailer') { |*args| observed << args.last }
    expect(process_event_email.state).to eq('sent')
    expect(observed).to be_empty
    expect(event_messages.size).to eq(1)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  context 'when the canonical complaint role is not explicitly assigned' do
    let(:definition) { super().tap { |value| value['roles']['thiago'] = [] } }

    it 'does not infer a canonical recipient role from administrator access' do
      expect(process_event_email).to have_attributes(state: 'blocked', attempt_number: 0)
      expect(event_messages).to be_empty
    end
  end

  context 'with an immediate native legal-risk event' do
    let(:email_rule) { 'R11' }
    let(:definition) { super().tap { |value| value['roles']['legal'] = [email_recipient.id]; value['roles']['thiago'] = [] } }

    it 'delivers only to the designated legal role behind current notes and source ACL' do
      expect(process_event_email).to have_attributes(state: 'sent', attempt_number: 1)
      expect(event.reload.evidence).to include('internal_only' => true)
      expect(event_messages.size).to eq(1)
      expect(event_messages.first.body.decoded).not_to include('notificação', 'PRIVATE-EVENT-EVIDENCE')
    end
  end
end

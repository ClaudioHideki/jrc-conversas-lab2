# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcNico::Helpdesk::EmailDelivery do
  include_context 'NICO HelpDesk native event email'

  it 'prepares the real captured event but never sends from an outer transaction savepoint' do
    expect(ActiveRecord::Base.connection.transaction_open?).to be(true)
    allow(JrcNicoHelpdeskMailer).to receive(:with).and_call_original
    expect(process_event_email).to have_attributes(state: 'blocked', reason: 'durable_commit_required', claim_token: nil, attempt_number: 0)
    expect(event.reload).to have_attributes(state: 'prepared', reason: 'approval_required')
    expect(JrcNicoHelpdeskMailer).not_to have_received(:with)
    expect(event.evidence.fetch('evidence_note_ids')).not_to be_empty
    expect(JrcNico::Helpdesk::TicketProfile.find_by!(ticket: ticket).complaint).to be(true)
  end

  it 'keeps the finite workbook email rule and canonical-role mapping exact' do
    expect(JrcNico::Helpdesk::DeliveryAuthorization::EVENT_EMAIL_ROLES).to eq(
      'R02' => %w[n2 thiago cs], 'R03' => %w[director thiago], 'R06' => %w[supervisor thiago],
      'R07' => %w[n2 management], 'R08' => %w[director cs], 'R10' => %w[cs thiago], 'R11' => %w[legal thiago ceo]
    )
    expect(JrcNico::Helpdesk::Definition.defaults.fetch('rules').values.pluck('enabled')).to all(be(false))
  end

  context 'with a separately enabled native daily-report contract' do
    let(:definition) do
      super().tap { |value| value['daily'].merge!('enabled' => true, 'recipients' => [sd_account_user.id], 'channels' => ['email']) }
    end

    it 'retains the exact daily-report payload fingerprints independently from event provenance' do
      report = JrcNico::Helpdesk::DailyReport.create!(account: sd_account, recipient: sd_account_user, policy_version: policy,
                                                      report_date: Date.current, scope_digest: 'event-email-daily-compatibility', timezone: 'UTC',
                                                      cutoff_at: Time.current, payload: { 'ticket_ids' => [], 'visible_event_ids' => [] })
      daily = JrcNico::Helpdesk::DeliveryReceipt.create!(account: sd_account, recipient: sd_account_user,
                                                         source_type: 'daily_report', source_id: report.id, channel: 'email')
      with_modified_env FRONTEND_URL: 'https://r345-mail.example.test' do
        pointer = JrcNico::Helpdesk::EmailPointer.url(report)
        expected = JrcNico::Helpdesk::Definition.digest(
          'source_id' => report.id, 'policy_id' => policy.id, 'recipient_id' => sd_account_user.id,
          'channel' => 'email', 'pointer' => pointer, 'payload' => report.payload
        )
        expect(JrcNico::Helpdesk::EmailClaim.new(daily).fingerprints.fetch(:payload_digest)).to eq(expected)
        expect(pointer).to end_with("?report_id=#{report.id}")
      end
    end
  end
end

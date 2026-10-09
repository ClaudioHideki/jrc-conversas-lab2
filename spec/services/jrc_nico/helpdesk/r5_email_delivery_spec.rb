# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcNico::Helpdesk::EmailDelivery do
  include_context 'JRC Service Desk domain'

  before { sd_account.update!(custom_attributes: { 'nico_enabled' => true }) }

  it 'does not confuse a fixture savepoint with a committed external delivery claim' do
    definition = JrcNico::Helpdesk::Definition.defaults
    policy = JrcNico::Helpdesk::PolicyVersion.create!(account: sd_account, author: sd_account_user, number: 1, state: 'draft', enabled: false,
                                                      definition: definition, digest: JrcNico::Helpdesk::Definition.digest(definition))
    report = JrcNico::Helpdesk::DailyReport.create!(account: sd_account, recipient: sd_account_user, policy_version: policy,
                                                    report_date: Date.current, scope_digest: 'outer-transaction-proof', timezone: 'UTC',
                                                    cutoff_at: Time.current,
                                                    payload: { 'ticket_ids' => [], 'visible_event_ids' => [] })
    receipt = JrcNico::Helpdesk::DeliveryReceipt.create!(account: sd_account, recipient: sd_account_user,
                                                         source_type: 'daily_report', source_id: report.id, channel: 'email')
    expect(ActiveRecord::Base.connection.transaction_open?).to be(true)
    allow(JrcNicoHelpdeskMailer).to receive(:with).and_call_original
    expect(described_class.new(receipt).call).to have_attributes(state: 'blocked', reason: 'durable_commit_required', claim_token: nil)
    expect(JrcNicoHelpdeskMailer).not_to have_received(:with)
  end
end

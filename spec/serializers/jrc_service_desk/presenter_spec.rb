# frozen_string_literal: true
require 'rails_helper'

RSpec.describe JrcServiceDesk::Presenter do
  include_context 'JRC Service Desk domain'
  let(:presenter) { described_class.new(user_context: sd_context) }

  it 'explicitly projects IDs and permissions, without raw contract, blob or database metadata' do
    row = sd_ticket
    result = presenter.ticket(row)
    expect(result[:id]).to eq(row.id.to_s)
    expect(result[:unit_id]).to eq(sd_unit.id.to_s)
    # The fixture has no published lifecycle policy authorizing work-status changes.
    expect(result[:permissions]).to include(show: true, change_work_status: false, transition: false, resolve: false)
    expect(result[:sla][:state]).to eq('unavailable')
    expect(result.keys & %i[request_fingerprint idempotency_key contract_conditions files]).to be_empty
  end

  it 'never projects denied unit data, including for admin' do
    sd_as_admin!
    hidden = create(:jrc_sd_ticket, unit: sd_other_unit)
    expect { presenter.ticket(hidden) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'redacts unknown event keys instead of forwarding arbitrary event JSON' do
    row = sd_ticket
    event = create(:jrc_sd_event, ticket: row, event_type: 'ticket_updated',
                   data: { title: ['before', 'after'], financial_secret: 999, blob_url: 'not-forwarded' })
    result = presenter.related(event, 'events')
    expect(result[:data]).to eq('title' => ['before', 'after'])
    expect(result[:author][:id]).to eq(sd_account_user.id.to_s)
  end

  it 'cannot present an unrelated conversation link merely because its ticket is readable' do
    row = sd_ticket
    link = create(:jrc_sd_conversation_link, ticket: row)
    expect { presenter.related(link, 'conversations') }.to raise_error(Pundit::NotAuthorizedError)
  end
end

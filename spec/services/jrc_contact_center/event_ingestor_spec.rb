# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcContactCenter::EventIngestor do
  let(:account) { create(:account) }
  let(:payload) do
    {
      schema_version: '1.0',
      event_id: SecureRandom.uuid,
      event_type: 'call.created',
      occurred_at: Time.current.iso8601,
      provider: 'jrc_pabx',
      call_session_id: SecureRandom.uuid,
      correlation_id: SecureRandom.uuid,
      payload: { direction: 'inbound' }
    }
  end

  it 'stores one canonical event and deduplicates an identical retry' do
    first = described_class.new(account: account).call(payload, signature_verified: true)
    second = described_class.new(account: account).call(payload, signature_verified: true)

    expect(first.created).to be(true)
    expect(second.created).to be(false)
    expect(second.record.id).to eq(first.record.id)
    expect(first.record).to have_attributes(status: 'pending', signature_verified: true)
  end

  it 'rejects a replay that reuses the event id with a different payload' do
    described_class.new(account: account).call(payload, signature_verified: true)
    changed = payload.deep_dup
    changed[:payload] = { direction: 'outbound' }

    expect { described_class.new(account: account).call(changed, signature_verified: true) }
      .to raise_error(ArgumentError, 'event replay payload mismatch')
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcContactCenter::EventReconciler do
  let(:account) { create(:account) }
  let(:correlation_id) { SecureRandom.uuid }
  let(:session_id) { SecureRandom.uuid }

  def ingest(type, event_id: SecureRandom.uuid, payload: {})
    result = JrcContactCenter::EventIngestor.new(account: account).call(
      {
        schema_version: '1.0',
        event_id: event_id,
        event_type: type,
        occurred_at: Time.current.iso8601,
        provider: 'jrc_pabx',
        call_session_id: session_id,
        correlation_id: correlation_id,
        payload: payload
      },
      signature_verified: true
    )
    described_class.new(event_record: result.record).call
  end

  it 'keeps one logical call session across lifecycle events' do
    ingest('call.created', payload: { direction: 'inbound', ani: '5511999999999', dnis: '0800' })
    ingest('call.answered')
    ingest('call.ended')

    session = JrcContactCenter::CallSession.find_by!(account: account, correlation_id: correlation_id)
    expect(session).to have_attributes(status: 'ended', external_session_id: session_id)
    expect(JrcContactCenter::CallSession.where(account: account).count).to eq(1)
  end

  it 'does not regress a terminal call when an older lifecycle event arrives late' do
    ingest('call.created', payload: { direction: 'inbound' })
    ingest('call.ended')
    ingest('call.created', payload: { direction: 'inbound', ani: '5511888888888' })
    ingest('call.answered')

    session = JrcContactCenter::CallSession.find_by!(account: account, correlation_id: correlation_id)
    expect(session.status).to eq('ended')
  end

  it 'does not replay IVR side effects from a stale inbox instance after locking' do
    ingest('call.created', payload: { direction: 'inbound' })
    event = JrcContactCenter::EventIngestor.new(account: account).call(
      { schema_version: '1.0', event_id: SecureRandom.uuid, event_type: 'ivr.menu.entered', occurred_at: Time.current.iso8601,
        provider: 'jrc_pabx', correlation_id: correlation_id, payload: { menu_key: 'test-menu' } }, signature_verified: true
    ).record
    stale = JrcContactCenter::EventInbox.find(event.id)

    described_class.new(event_record: event).call
    described_class.new(event_record: stale).call

    expect(stale.reload).to have_attributes(status: 'processed', attempts: 1)
    expect(JrcContactCenter::IvrEvent.where(account: account).count).to eq(1)
  end

  it 'does not attach an event missing call identity to an unrelated session with a null external id' do
    JrcContactCenter::CallSession.create!(account: account, correlation_id: SecureRandom.uuid, direction: 'inbound', started_at: Time.current)
    event = JrcContactCenter::EventIngestor.new(account: account).call(
      { schema_version: '1.0', event_id: SecureRandom.uuid, event_type: 'ivr.menu.entered', occurred_at: Time.current.iso8601,
        provider: 'jrc_pabx', payload: {} }, signature_verified: true
    ).record

    described_class.new(event_record: event).call

    expect(event.reload.status).to eq('failed')
    expect(JrcContactCenter::IvrEvent.where(account: account)).to be_empty
  end
end

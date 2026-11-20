require 'rails_helper'

# The existing normalized inbox contract is simulated here, not a real provider signature or ACK.
RSpec.describe 'Frozen ending reason compatibility with native normalized events' do
  include_context 'with a frozen ending reason catalogue'

  it 'preserves the first observed policy while the reconciler corrects started_at from a late call.created event' do
    occurred = Time.current.floor(6)
    correlation = SecureRandom.uuid
    external = SecureRandom.uuid
    first = JrcContactCenter::EventIngestor.new(account: account).call(
      { schema_version: '1.0', event_id: SecureRandom.uuid, event_type: 'call.created', occurred_at: occurred.iso8601(6),
        provider: 'jrc_pabx', call_session_id: external, correlation_id: correlation, payload: { direction: 'inbound' } },
      signature_verified: true
    ).record
    JrcContactCenter::EventReconciler.new(event_record: first).call
    expect(first.reload.status).to eq('processed')
    call = JrcContactCenter::CallSession.find_by!(account: account, correlation_id: correlation)
    original = call.ending_reason_version_id
    expect(original).to be_present
    expect(call.ending_reason_captured_started_at).to eq(occurred)
    earlier = occurred - 5.seconds
    correction = JrcContactCenter::EventIngestor.new(account: account).call(
      { schema_version: '1.0', event_id: SecureRandom.uuid, event_type: 'call.created', occurred_at: earlier.iso8601(6),
        provider: 'jrc_pabx', call_session_id: external, correlation_id: correlation, payload: { direction: 'inbound' } },
      signature_verified: true
    ).record
    JrcContactCenter::EventReconciler.new(event_record: correction).call
    expect(correction.reload.status).to eq('processed')
    expect(call.reload.started_at).to eq(earlier)
    expect(call.ending_reason_version_id).to eq(original)
    expect(call.ending_reason_captured_started_at).to eq(occurred)
  end
end

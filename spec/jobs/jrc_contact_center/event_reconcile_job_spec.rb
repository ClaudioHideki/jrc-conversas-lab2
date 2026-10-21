# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcContactCenter::EventReconcileJob do
  let(:account) { create(:account) }
  let(:event) do
    JrcContactCenter::EventIngestor.new(account: account).call(
      { schema_version: '1.0', event_id: 'created-1', event_type: 'call.created', occurred_at: Time.current.iso8601,
        provider: 'jrc_pabx', correlation_id: 'call-1' }, signature_verified: true
    ).record
  end

  it 'enqueues reconciliation when a pending event is created in an enabled account' do
    account.enable_features!('jrc_contact_center')

    expect { event }.to have_enqueued_job(described_class).with(account.id, kind_of(Integer))
  end

  it 'does not reconcile an event after its account feature is disabled' do
    record = event
    described_class.perform_now(account.id, record.id)

    expect(record.reload.status).to eq('pending')
    expect(JrcContactCenter::CallSession.where(account: account)).to be_empty
  end

  it 'does not load another account event even with a valid event identifier' do
    foreign = create(:account)
    foreign.enable_features!('jrc_contact_center')

    expect { described_class.perform_now(foreign.id, event.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(event.reload.status).to eq('pending')
  end
end

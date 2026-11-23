require 'rails_helper'
require Rails.root.join('script/jrc_call_center_ending_origin_upgrade')

RSpec.describe JrcContactCenter::SyntheticEndingOriginUpgrade do
  include_context 'with native ending execution original evidence'

  it 'takes the pre-upgrade baseline from persisted native trigger values instead of a stale attendance object' do
    qualification
    stored = JrcContactCenter::CallSession.where(account: account).find(source_call.id)
    expect(stored.ending_reason_version_id).not_to be_nil
    expect(stored.ending_reason_captured_started_at).not_to be_nil
    expect(source_call.attributes).not_to eq(stored.attributes)

    baseline = described_class.new.send(:snapshot, source_call)
    expected = Digest::SHA256.hexdigest(ActiveSupport::JSON.encode(stored.attributes))

    expect(baseline).to eq(type: stored.class.name, id: stored.id, columns: stored.attributes.keys, digest: expected)
    expect(baseline).not_to have_key(:attributes)
    expect(source_call.attributes).to eq(stored.attributes)
  end
end

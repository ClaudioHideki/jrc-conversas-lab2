require 'rails_helper'

RSpec.describe JrcApprovals::RequestSerializer, :approval_core do
  include_context 'with all-scope native pause approval'

  it 'serializes only scoped immutable names and digests without exposing another company or the personal justification' do
    publish_all_pause_policies
    create_reviewed_pause
    row = described_class.new(pause_requests.first).as_json
    origin = row.fetch('origin')
    expect(origin).to include('kind' => 'contact_center_pause', 'own_scope_only' => true, 'historical' => true)
    expect(origin.fetch('scope_unit_ids')).to eq([units.first.id.to_s])
    expect(origin.fetch('scope_unit_names')).to eq([units.first.name])
    expect(origin.to_json).not_to include(units.last.name)
    expect(origin).not_to have_key('justification')
    expect(origin).not_to have_key('coverage')
    expect(origin.fetch('provider_confirmed')).to be(false)
  end
end

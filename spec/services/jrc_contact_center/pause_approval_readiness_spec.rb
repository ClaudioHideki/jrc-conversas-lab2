require 'rails_helper'

RSpec.describe JrcContactCenter::PauseApprovalReadiness, :approval_core do
  include_context 'with all-scope native pause approval'

  subject(:readiness) { described_class.new(account: account, member: member) }

  it 'projects captured operational unit names for every coherent owned scope without applying a pending pause' do
    publish_all_pause_policies
    row = create_reviewed_pause
    value = readiness.call(row)
    expected = units.map { |unit| { unit_ids: [unit.id.to_s], unit_names: [unit.name] } }
    expect(value.fetch(:scopes).map { |scope| scope.slice(:unit_ids, :unit_names) }).to eq(expected)
    expect(value.fetch(:status)).to eq('approval_required')
    expect(row.reload.state).to eq('pending')
    expect(JrcContactCenter::AgentStateEvent.where(account: account, state: 'paused')).to be_empty
  end

  it 'keeps captured names immutable and withholds the projection after the native unit context changes' do
    publish_all_pause_policies
    row = create_reviewed_pause
    review = JrcContactCenter::PauseApprovalReview.find_by!(account: account, deferred_pause_request_id: row.id)
    original = review.payload.deep_dup
    name = units.last.name
    units.last.update!(name: 'SYNTHETIC renamed after the captured review')
    expect(readiness.call(row)).to include(status: 'review_required', scopes: [])
    expect(review.reload.payload).to eq(original)
    expect(review.scopes.order(:id).last.unit_names).to eq([name])
  end

  it 'returns no captured names after the owner loses current operating eligibility' do
    publish_all_pause_policies
    row = create_reviewed_pause
    JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member).update!(eligible: false)
    expect(readiness.call(row)).to include(status: 'review_required', scopes: [])
    expect(row.reload.state).to eq('pending')
    expect(JrcContactCenter::AgentStateEvent.where(account: account, state: 'paused')).to be_empty
  end
end

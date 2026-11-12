require 'rails_helper'

RSpec.describe JrcRelationship::WeightedCapacity do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:target) { create(:user, account: account, role: :agent) }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: actor)) }
  let(:service) { JrcRelationship::ReviewedPortfolioBatch.new(context) }
  let(:first) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:second) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:inputs) { { 'ids' => [first.id, second.id], 'operation' => 'assign', 'owner_id' => target.id, 'request_id' => SecureRandom.uuid } }
  let(:factors) { { 'base' => 2, 'complexity_factor' => 1.5, 'risk_factor' => 2, 'journey_factor' => 1, 'activity_effort' => 1 } }
  let(:limits) do
    [{ 'user_id' => actor.id, 'maximum' => 100, 'availability' => 1, 'dedication' => 1 },
     { 'user_id' => target.id, 'maximum' => 8, 'availability' => 1, 'dedication' => 1, 'unit' => 'points' }]
  end
  let(:config) { JrcRelationship::Configuration.create!(account: account, rules: { portfolio_capacity_limits: limits }) }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'uses explicit Word factors, preserves reviewed receipts and executes the actual weighted transfer' do
    first.update!(settings: { 'capacity_workload' => { 'points' => factors } })
    second.update!(settings: { 'capacity_workload' => { 'points' => factors.merge('base' => 0) } })
    config
    preview = service.preview(inputs)
    expect(preview.fetch('capacity').first).to include('unit' => 'points', 'current' => 0, 'incoming' => 8, 'effective_capacity' => 8)
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    service.advance(preview.fetch('id'), limit: 1)
    expect(service.advance(preview.fetch('id')).fetch('state')).to eq('completed')
    expect([first.reload.owner_id, second.reload.owner_id]).to eq([target.id, target.id])
  end

  it 'keeps missing workload unavailable instead of substituting customer counts or invented weights' do
    config
    preview = service.preview(inputs)
    expect(preview.fetch('capacity').first).to include('blocker' => 'capacity_workload_missing', 'unit' => 'points')
    expect { service.approve(preview.fetch('id'), digest: preview.fetch('digest')) }.to raise_error(ArgumentError, /capacity/)
    expect(first.reload.owner_id).to eq(actor.id)
  end

  it 'uses supplied equivalent hours and exact effective-capacity arithmetic, without any implicit hours conversion' do
    first.update!(settings: { 'capacity_workload' => { 'hours' => 0.75 } })
    second.update!(settings: { 'capacity_workload' => { 'hours' => 0.5 } })
    limits.last.merge!('unit' => 'hours', 'maximum' => 2.5, 'availability' => 0.8, 'dedication' => 0.5)
    config
    preview = service.preview(inputs)
    expect(preview.fetch('capacity').first).to include('unit' => 'hours', 'projected' => 1.25, 'effective_capacity' => 1.0,
                                                       'blocker' => 'capacity_exceeded')
    expect do
      first.update!(owner: target)
      second.update!(owner: target)
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(second.reload.owner_id).to eq(actor.id)
  end

  it 'rechecks changed destination baseline workloads and prevents direct workload increases beyond the native limit' do
    first.update!(settings: { 'capacity_workload' => { 'hours' => 1 } })
    second.update!(settings: { 'capacity_workload' => { 'hours' => 1 } })
    baseline = JrcRelationship::Assignment.create!(account: account, owner: target, contact: create(:contact, account: account),
                                                   settings: { 'capacity_workload' => { 'hours' => 1 } })
    limits.last.merge!('unit' => 'hours', 'maximum' => 4)
    config
    preview = service.preview(inputs)
    baseline.update!(settings: { 'capacity_workload' => { 'hours' => 2 } })
    expect { service.approve(preview.fetch('id'), digest: preview.fetch('digest')) }.to raise_error(ArgumentError, /capacity changed/)
    expect { baseline.update!(settings: { 'capacity_workload' => { 'hours' => 5 } }) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(baseline.reload.settings.dig('capacity_workload', 'hours')).to eq(2)
  end
end

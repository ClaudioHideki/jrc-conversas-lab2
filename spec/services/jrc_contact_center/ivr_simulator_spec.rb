require 'rails_helper'

RSpec.describe JrcContactCenter::IvrSimulator do
  let(:account) { create(:account) }
  let(:operator) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: operator) }
  let(:access) { JrcContactCenter::AccessScope.new(user_context: { account: account, account_user: member, user: operator }) }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, code: 'LOCAL', name: 'SYNTHETIC local', kind: 'sac') }
  let(:queue) { JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'LOCAL', name: 'SYNTHETIC local') }
  let(:definition) do
    { 'schema_version' => 1, 'start' => 'entry', 'nodes' => [
      { 'id' => 'entry', 'type' => 'menu', 'timeout_seconds' => 10, 'max_attempts' => 2,
        'options' => [{ 'digit' => '1', 'target' => 'route' }], 'on_timeout' => 'end', 'on_invalid' => 'end' },
      { 'id' => 'route', 'type' => 'queue', 'queue_id' => queue.id.to_s }, { 'id' => 'end', 'type' => 'end' }
    ] }
  end
  let(:graph) { JrcContactCenter::IvrGraph.new(definition, access: access, unit_id: unit.id) }
  let(:simulator) { described_class.new(graph: graph) }

  before { account.enable_features!('jrc_contact_center') }

  it 'returns a local queue destination without creating a call, provider command or inbox event' do
    before = [JrcContactCenter::CallSession.count, JrcContactCenter::Command.count, JrcContactCenter::EventInbox.count]
    result = simulator.call(input: '1')
    expect(result).to include(local_only: true, provider_applied: false, outcome: 'queue_destination', queue_id: queue.id.to_s)
    expect(result[:trace].pluck(:node_id)).to eq(%w[entry route])
    expect([JrcContactCenter::CallSession.count, JrcContactCenter::Command.count, JrcContactCenter::EventInbox.count]).to eq(before)
    expect(result[:trace].all? { |row| row.keys.exclude?(:input) }).to be(true)
  end

  it 'takes the configured local timeout path without waiting or contacting the provider' do
    result = simulator.call
    expect(result[:outcome]).to eq('ended')
    expect(result[:trace].first).to include(event: 'timeout')
    expect(result[:trace].pluck(:node_id)).to eq(%w[entry end])
  end

  it 'retries invalid digits and follows the explicitly configured attempt limit' do
    result = simulator.call(input: '99')
    expect(result[:outcome]).to eq('ended')
    expect(result[:trace].pluck(:event).compact).to eq(%w[retry_invalid invalid_limit])
  end

  it 'resets per-simulation state rather than reusing a previous input or trace' do
    expect(simulator.call(input: '1')[:outcome]).to eq('queue_destination')
    result = simulator.call
    expect(result[:outcome]).to eq('ended')
    expect(result[:trace].length).to eq(2)
  end

  it 'bounds a legal retry cycle without falsely claiming that a destination was reached' do
    definition['nodes'][0]['on_timeout'] = 'entry'
    result = simulator.call
    expect(result[:outcome]).to eq('step_limit')
    expect(result[:trace].length).to eq(described_class::MAX_STEPS)
    expect(result[:provider_applied]).to be(false)
  end

  ['abc', '1 2', '1' * 129, nil, false].each do |input|
    it "rejects unsupported local input #{input.inspect} without recording it" do
      expect { simulator.call(input: input) }.to raise_error(JrcContactCenter::OperationError, 'ivr_invalid_simulation_input')
    end
  end

  it 'denies reuse after individual eligibility is revoked' do
    expect(simulator.call(input: '1')[:outcome]).to eq('queue_destination')
    JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(eligible: false)
    expect { simulator.call(input: '1') }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'denies reuse after the native feature is disabled' do
    expect(simulator.call(input: '1')[:outcome]).to eq('queue_destination')
    account.disable_features!('jrc_contact_center')
    expect { simulator.call(input: '1') }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rechecks the destination state instead of retaining a previous queue validation' do
    expect(simulator.call(input: '1')[:outcome]).to eq('queue_destination')
    queue.update!(status: 'inactive')
    expect { simulator.call(input: '1') }.to raise_error(JrcContactCenter::OperationError, 'ivr_unavailable_queue')
  end
  %w[* #].each do |digit|
    it "supports the explicit DTMF option #{digit} without interpreting it as a command" do
      definition['nodes'][0]['options'][0]['digit'] = digit
      expect(simulator.call(input: digit)[:outcome]).to eq('queue_destination')
    end
  end

end

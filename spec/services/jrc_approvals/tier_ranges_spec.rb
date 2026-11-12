require 'rails_helper'

RSpec.describe JrcApprovals::TierRanges, :approval_core do
  let(:scope) { approval_scope }
  let(:author) { approval_actor(scope) }
  let(:manager) { approval_actor(scope) }
  let(:director) { approval_actor(scope) }
  let(:entry) { JrcApprovals::Catalog.fetch('synthetic.review') }
  let(:money) { ->(amount) { { 'amount_cents' => amount, 'currency' => 'BRL' } } }
  let(:definition) do
    draft = approval_definition([manager])
    draft['schema_version'] = 2
    draft['steps'] << approval_definition([director])['steps'].first.merge('code' => 'director')
    draft.merge('tiers' => {
                  'field' => 'amount', 'currency' => 'BRL', 'min' => money.call(0), 'max' => nil, 'coverage' => 'complete',
                  'rows' => [
                    { 'min' => money.call(0), 'max' => money.call(2000), 'min_inclusive' => true, 'max_inclusive' => true,
                      'step_codes' => ['review'] },
                    { 'min' => money.call(2000), 'max' => nil, 'min_inclusive' => false, 'max_inclusive' => false, 'step_codes' => ['director'] }
                  ]
                })
  end

  [0, 1200, 2000, 2001, 9_007_199_254_740_991].each do |amount|
    it "selects the exact native monetary range at #{amount} minor units" do
      validated = JrcApprovals::Definition.validate!(definition, entry)
      selected = described_class.new(validated, entry).steps!('amount' => money.call(amount))
      expect(selected.pluck('code')).to eq(amount <= 2000 ? ['review'] : ['director'])
    end
  end

  it 'compares decimals beyond Float precision using the native typed comparator' do
    draft = definition.deep_dup
    draft['tiers'].merge!('field' => 'quantity', 'currency' => nil, 'min' => '0')
    first, last = draft['tiers']['rows']
    first['min'] = '0'
    first['max'] = '20.00000000000000001'
    last['min'] = '20.00000000000000001'
    expect(described_class.new(draft, entry).steps!('quantity' => '20.00000000000000001').pluck('code')).to eq(['review'])
    expect(described_class.new(draft, entry).steps!('quantity' => '20.00000000000000002').pluck('code')).to eq(['director'])
  end

  it 'accepts an explicitly unbounded complete domain without assuming a zero lower limit' do
    definition['tiers']['min'] = nil
    definition['tiers']['rows'].first.merge!('min' => nil, 'min_inclusive' => false)
    expect(described_class.new(definition, entry).steps!('amount' => money.call(-10)).pluck('code')).to eq(['review'])
  end

  it 'rejects a value outside the declared domain even if a partial gap is allowed' do
    definition['tiers']['coverage'] = 'partial'
    expect { described_class.new(definition, entry).steps!('amount' => money.call(-1)) }
      .to raise_error(JrcApprovals::Error, 'TIER_NOT_APPLICABLE')
  end

  it 'rejects two owners of the same exact boundary instead of silently choosing the first' do
    definition['tiers']['rows'].last['min_inclusive'] = true
    expect { JrcApprovals::Definition.validate!(definition, entry) }.to raise_error(JrcApprovals::Error, 'TIER_OVERLAP')
  end

  it 'rejects reversed or overlapping range order' do
    definition['tiers']['rows'].reverse!
    expect { JrcApprovals::Definition.validate!(definition, entry) }.to raise_error(JrcApprovals::Error, 'TIER_OVERLAP')
  end

  it 'rejects an uncovered shared boundary when full coverage is required' do
    definition['tiers']['rows'].first['max_inclusive'] = false
    expect { JrcApprovals::Definition.validate!(definition, entry) }.to raise_error(JrcApprovals::Error, 'TIER_GAP')
  end

  it 'rejects missing declared domain endpoints under complete coverage' do
    definition['tiers']['rows'].first['min_inclusive'] = false
    expect { JrcApprovals::Definition.validate!(definition, entry) }.to raise_error(JrcApprovals::Error, 'TIER_GAP')
  end

  it 'allows an explicit partial gap but cannot create a plan inside the gap' do
    definition['tiers']['coverage'] = 'partial'
    definition['tiers']['rows'].last['min'] = money.call(3000)
    expect(JrcApprovals::Definition.validate!(definition, entry)).to eq(definition)
    expect { described_class.new(definition, entry).steps!('amount' => money.call(2500)) }
      .to raise_error(JrcApprovals::Error, 'TIER_NOT_APPLICABLE')
  end

  it 'rejects mixed currencies and nonnumeric catalog fields without coercing them' do
    definition['tiers']['rows'].first['max']['currency'] = 'USD'
    expect { JrcApprovals::Definition.validate!(definition, entry) }.to raise_error(JrcApprovals::Error)
    definition['tiers']['field'] = 'code'
    expect { JrcApprovals::Definition.validate!(definition, entry) }.to raise_error(JrcApprovals::Error)
  end

  it 'rejects unused or unknown approval steps and malformed inclusion flags' do
    definition['tiers']['rows'].last['step_codes'] = ['not_installed']
    expect { JrcApprovals::Definition.validate!(definition, entry) }.to raise_error(JrcApprovals::Error)
    definition['tiers']['rows'].last['step_codes'] = ['review']
    expect { JrcApprovals::Definition.validate!(definition, entry) }.to raise_error(JrcApprovals::Error)
    definition['tiers']['rows'].last['step_codes'] = ['director']
    definition['tiers']['rows'].last['min_inclusive'] = 'false'
    expect { JrcApprovals::Definition.validate!(definition, entry) }.to raise_error(JrcApprovals::Error)
  end

  it 'uses the same persisted roster in the native simulator and request creation, with no simulator writes' do
    policy = approval_publish(scope, author, definition)
    before = [JrcApprovals::Request.count, JrcApprovals::Decision.count, JrcApprovals::AuditEvent.count, Notification.count]
    simulation = JrcApprovals::Simulation.new(account: scope[:account], user: author.user).call(key: 'synthetic.review', resource_id: scope[:unit].id)
    expect(simulation[:effects]).to eq([])
    expect([JrcApprovals::Request.count, JrcApprovals::Decision.count, JrcApprovals::AuditEvent.count, Notification.count]).to eq(before)
    record = approval_request(scope, author)
    expect(record.policy_version_id).to eq(policy.current_version_id)
    expect(record.stage_plan).to eq(simulation[:versions].first[:plan])
    expect(record.stage_plan.pluck('code')).to eq(['review'])
  end

  it 'prevents the lower-tier actor from voting on the higher native stage and rechecks current membership' do
    scope[:unit].update!(settings: scope[:unit].settings.merge('test_amount' => 2001))
    approval_publish(scope, author, definition)
    record = approval_request(scope, author)
    expect(record.stage_plan.pluck('code')).to eq(['director'])
    expect { approval_vote(scope, manager, record, step_code: 'director') }.to raise_error(Pundit::NotAuthorizedError)
    JrcCrm::UserBusinessUnit.where(account_id: scope[:account].id, user_id: director.user_id).find_each { |unit| unit.update!(active: false) }
    expect { approval_vote(scope, director, record, step_code: 'director') }.to raise_error(Pundit::NotAuthorizedError)
    expect(record.reload.decisions).to be_empty
    expect(record.state).to eq('pending')
  end

  it 'blocks request creation and the simulator on an uncovered value without partial request or audit writes' do
    definition['tiers']['coverage'] = 'partial'
    definition['tiers']['rows'].first['max'] = money.call(1000)
    approval_publish(scope, author, definition)
    before = [JrcApprovals::Request.count, JrcApprovals::AuditEvent.count]
    expect { approval_request(scope, author) }.to raise_error(JrcApprovals::Error, 'TIER_NOT_APPLICABLE')
    simulation = JrcApprovals::Simulation.new(account: scope[:account], user: author.user).call(key: 'synthetic.review', resource_id: scope[:unit].id)
    expect(simulation).to include(predicted_state: 'blocked', conflict: 'TIER_NOT_APPLICABLE', effects: [])
    expect([JrcApprovals::Request.count, JrcApprovals::AuditEvent.count]).to eq(before)
  end

  it 'preserves an in-flight v1 snapshot and plan after editing and publishing a tiered version' do
    original = approval_publish(scope, author, approval_definition([manager]))
    old_version = original.current_version
    record = approval_request(scope, author)
    captured = record.attributes.slice('snapshot', 'stage_plan', 'fingerprint', 'policy_version_id')
    service = JrcApprovals::Policies.new(account: scope[:account], user: author.user)
    service.edit!(policy_id: original.id, expected_version: original.reload.lock_version, name: original.name, definition: definition)
    service.validate!(policy_id: original.id, expected_version: original.reload.lock_version)
    service.publish!(policy_id: original.id, expected_version: original.reload.lock_version)
    approval_vote(scope, manager, record)
    expect(record.reload.state).to eq('approved')
    expect(record.attributes.slice(*captured.keys)).to eq(captured)
    expect(old_version.reload.definition['schema_version']).to eq(1)
    expect(original.reload.current_version.definition['schema_version']).to eq(2)
  end

  it 'does not allow v2 to omit the mandatory financial stage from a gratuity tier' do
    definition['steps'][0]['code'] = 'gratuidade_comercial'
    definition['steps'][1]['code'] = 'gratuidade_financeira'
    definition['execution'] = 'sequential'
    definition['reopen_mode'] = 'restart_all'
    definition['tiers']['rows'][0]['step_codes'] = ['gratuidade_comercial']
    definition['tiers']['rows'][1]['step_codes'] = ['gratuidade_financeira']
    expect { JrcApprovals::GratuityAuthorities.new(account: scope[:account], company_id: scope[:company].id).validate_definition!(definition) }
      .to raise_error(JrcApprovals::Error, 'INVALID_GRATUITY_SEQUENCE')
  end

  it 'rejects a pending lower-tier decision when the real source crosses into a higher tier' do
    approval_publish(scope, author, definition)
    record = approval_request(scope, author)
    original = record.attributes.slice('snapshot', 'stage_plan', 'fingerprint')
    scope[:unit].update!(settings: scope[:unit].settings.merge('test_amount' => 2001))
    expect { approval_vote(scope, manager, record) }.to raise_error(JrcApprovals::Error, 'CONTEXT_STALE')
    expect(record.reload.attributes.slice(*original.keys)).to eq(original)
    expect(record.decisions).to be_empty
    next_request = approval_request(scope, author, key: 'higher-source-revision')
    expect(next_request.stage_plan.pluck('code')).to eq(['director'])
  end

  it 'accepts a declared single-point domain only with both inclusive endpoints' do
    definition['tiers'].merge!('min' => money.call(2000), 'max' => money.call(2000))
    definition['tiers']['rows'] = [{ 'min' => money.call(2000), 'max' => money.call(2000),
                                     'min_inclusive' => true, 'max_inclusive' => true, 'step_codes' => %w[review director] }]
    expect(described_class.new(definition, entry).steps!('amount' => money.call(2000)).pluck('code')).to eq(%w[review director])
    definition['tiers']['rows'].first['max_inclusive'] = false
    expect { JrcApprovals::Definition.validate!(definition, entry) }.to raise_error(JrcApprovals::Error)
  end

  it 'rejects imprecise JSON integer bounds without limiting real values in an unbounded tier' do
    definition['tiers']['max'] = money.call(9_007_199_254_740_992)
    expect { JrcApprovals::Definition.validate!(definition, entry) }.to raise_error(JrcApprovals::Error, 'INVALID_TIER_DEFINITION')
    definition['tiers']['max'] = nil
    definition['tiers']['rows'].last.merge!('max' => nil, 'max_inclusive' => false)
    expect(described_class.new(definition, entry).steps!('amount' => money.call(9_007_199_254_740_992)).pluck('code')).to eq(['director'])
  end
end

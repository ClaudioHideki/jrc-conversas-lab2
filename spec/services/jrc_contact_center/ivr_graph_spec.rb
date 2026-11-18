require 'rails_helper'

RSpec.describe JrcContactCenter::IvrGraph do
  let(:account) { create(:account) }
  let(:operator) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: operator) }
  let(:access) { JrcContactCenter::AccessScope.new(user_context: { account: account, account_user: member, user: operator }) }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, code: 'LOCAL', name: 'SYNTHETIC local unit', kind: 'sac') }
  let(:queue) { JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'LOCAL', name: 'SYNTHETIC local queue') }
  let(:definition) do
    { 'schema_version' => 1, 'start' => 'entry', 'nodes' => [
      { 'id' => 'entry', 'type' => 'menu', 'timeout_seconds' => 10, 'max_attempts' => 2,
        'options' => [{ 'digit' => '1', 'target' => 'route' }], 'on_timeout' => 'end', 'on_invalid' => 'end' },
      { 'id' => 'route', 'type' => 'queue', 'queue_id' => queue.id.to_s },
      { 'id' => 'end', 'type' => 'end' }
    ] }
  end

  before { account.enable_features!('jrc_contact_center') }

  it 'accepts an explicit local schema and resolves only active references in the same authorized unit' do
    graph = described_class.new(definition, access: access, unit_id: unit.id)
    expect(graph.data).to eq(definition)
    expect(graph.unit_id).to eq(unit.id.to_s)
    expect(graph.nodes.keys).to contain_exactly('entry', 'route', 'end')
  end

  [nil, false, [], {}, { 'schema_version' => 2, 'start' => 'end', 'nodes' => [{ 'id' => 'end', 'type' => 'end' }] }].each do |invalid|
    it "rejects malformed or unsupported JSON #{invalid.inspect} without accepting a provider contract" do
      expect { described_class.new(invalid, access: access, unit_id: unit.id) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ivr_graph')
    end
  end

  it 'rejects duplicate IDs instead of silently replacing a node in the graph index' do
    definition['nodes'] << { 'id' => 'route', 'type' => 'end' }
    expect do
      described_class.new(definition, access: access, unit_id: unit.id)
    end.to raise_error(JrcContactCenter::OperationError, 'ivr_duplicate_or_missing_node')
  end

  it 'rejects an unknown start node' do
    definition['start'] = 'missing'
    expect do
      described_class.new(definition, access: access, unit_id: unit.id)
    end.to raise_error(JrcContactCenter::OperationError, 'ivr_duplicate_or_missing_node')
  end

  it 'rejects duplicate DTMF options rather than choosing an arbitrary first match' do
    definition['nodes'][0]['options'] << { 'digit' => '1', 'target' => 'end' }
    expect do
      described_class.new(definition, access: access, unit_id: unit.id)
    end.to raise_error(JrcContactCenter::OperationError, 'ivr_duplicate_dtmf')
  end

  it 'rejects a nonexistent option target' do
    definition['nodes'][0]['options'][0]['target'] = 'missing'
    expect do
      described_class.new(definition, access: access, unit_id: unit.id)
    end.to raise_error(JrcContactCenter::OperationError, 'ivr_missing_target')
  end

  it 'rejects a closed loop even when an unrelated orphan terminal exists' do
    entry = definition['nodes'][0]
    entry['options'][0]['target'] = 'entry'
    entry['on_timeout'] = entry['on_invalid'] = 'entry'
    expect { described_class.new(definition, access: access, unit_id: unit.id) }.to raise_error(JrcContactCenter::OperationError, 'ivr_closed_loop')
  end

  it 'allows a retry cycle with an explicit logical exit' do
    definition['nodes'][0]['on_timeout'] = 'entry'
    expect(described_class.new(definition, access: access, unit_id: unit.id).nodes.length).to eq(3)
  end

  it 'rejects an inactive destination with the same unavailable response as a nonexistent one' do
    queue.update!(status: 'inactive')
    expect do
      described_class.new(definition, access: access, unit_id: unit.id)
    end.to raise_error(JrcContactCenter::OperationError, 'ivr_unavailable_queue')
  end

  it 'rejects a queue in a different account' do
    foreign = create(:account)
    foreign_unit = JrcContactCenter::Unit.create!(account: foreign, code: 'FOREIGN', name: 'SYNTHETIC foreign', kind: 'sac')
    foreign_queue = JrcContactCenter::Queue.create!(account: foreign, unit: foreign_unit, code: 'FOREIGN', name: 'SYNTHETIC foreign')
    definition['nodes'][1]['queue_id'] = foreign_queue.id.to_s
    expect do
      described_class.new(definition, access: access, unit_id: unit.id)
    end.to raise_error(JrcContactCenter::OperationError, 'ivr_unavailable_queue')
  end

  it 'does not transfer a same-account queue into another local unit graph implicitly' do
    other_unit = JrcContactCenter::Unit.create!(account: account, code: 'OTHER', name: 'SYNTHETIC other', kind: 'sac')
    other_queue = JrcContactCenter::Queue.create!(account: account, unit: other_unit, code: 'OTHER', name: 'SYNTHETIC other')
    definition['nodes'][1]['queue_id'] = other_queue.id.to_s
    expect do
      described_class.new(definition, access: access, unit_id: unit.id)
    end.to raise_error(JrcContactCenter::OperationError, 'ivr_unavailable_queue')
  end

  it 'rejects an oversized queue identifier before it can overflow a PostgreSQL bigint' do
    definition['nodes'][1]['queue_id'] = '9999999999999999999'
    expect do
      described_class.new(definition, access: access, unit_id: unit.id)
    end.to raise_error(JrcContactCenter::OperationError, 'ivr_unavailable_queue')
  end

  it 'rejects an inaccessible unit rather than trusting a supplied unit identifier' do
    expect { described_class.new(definition, access: access, unit_id: '9999999999999999999') }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'checks current permissions even when the caller keeps an old access-policy instance' do
    expect(access.policy.configure?).to be(true)
    member.update!(custom_role: create(:custom_role, account: account, permissions: ['jrc_contact_center_view']))
    expect { described_class.new(definition, access: access, unit_id: unit.id) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'does not accept individual eligibility revocation through a cached scope' do
    expect(access.policy.configure?).to be(true)
    JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(eligible: false)
    expect { described_class.new(definition, access: access, unit_id: unit.id) }.to raise_error(Pundit::NotAuthorizedError)
  end

  ['unknown', 0, '1', 1.0].each do |version|
    it "does not reinterpret the schema identity #{version.inspect}" do
      definition['schema_version'] = version
      expect do
        described_class.new(definition, access: access, unit_id: unit.id)
      end.to raise_error(JrcContactCenter::OperationError, 'invalid_ivr_graph')
    end
  end

  it 'rejects provider commands or account overrides in the local definition' do
    definition['account_id'] = account.id
    definition['provider_command'] = 'not-a-native-operation'
    expect { described_class.new(definition, access: access, unit_id: unit.id) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ivr_graph')
  end

  it 'does not retain mutable caller data after validating a graph' do
    graph = described_class.new(definition, access: access, unit_id: unit.id)
    definition['nodes'][0]['options'][0]['target'] = 'missing'
    expect(graph.data['nodes'][0]['options'][0]['target']).to eq('route')
  end

  it 'does not let native administrator role bypass a configured corporate-unit boundary' do
    company = JrcCustomers::Company.create!(account: account, name: 'SYNTHETIC issuer', relationship_type: 'internal', active: true)
    business_unit = JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: 'SYNTHETIC own', code: 'OWN', active: true)
    JrcCrm::UserBusinessUnit.create!(account: account, user: operator, scope: 'BUSINESS_UNIT', company: company,
                                     business_unit: business_unit, active: true, structure_managed: true)
    unit.update!(settings: { 'issuer_company_id' => company.id, 'business_unit_id' => business_unit.id })
    other = JrcContactCenter::Unit.create!(account: account, code: 'UNMAPPED', name: 'SYNTHETIC restricted', kind: 'sac')
    expect(described_class.new(definition, access: access, unit_id: unit.id).unit_id).to eq(unit.id.to_s)
    expect { described_class.new(definition, access: access, unit_id: other.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  ["entry\n", "\nentry", 'entry with space', 'entry;code'].each do |id|
    it "rejects unsafe node identifier #{id.inspect}" do
      definition['nodes'][0]['id'] = definition['start'] = id
      expect do
        described_class.new(definition, access: access, unit_id: unit.id)
      end.to raise_error(JrcContactCenter::OperationError, 'invalid_ivr_graph')
    end
  end
end

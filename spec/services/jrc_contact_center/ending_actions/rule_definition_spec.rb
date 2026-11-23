require 'rails_helper'

# Prepared, unapplied and unexecuted. Shape acceptance never grants source or destination authority.
RSpec.describe JrcContactCenter::EndingActions::RuleDefinition do
  subject(:validator) { described_class.new }

  let(:task) do
    { 'project_id' => '11', 'due_after_days' => nil, 'attributes' => {
      'title' => 'SYNTHETIC follow-up', 'priority' => 'medium', 'estimated_minutes' => 0, 'board_column_id' => '12'
    } }
  end
  let(:scope) do
    { 'queue_scope_version_id' => '31', 'integrity_sha256' => 'a' * 64,
      'unit_id' => '21', 'issuer_company_id' => '41', 'business_unit_id' => nil }
  end
  let(:rule) do
    { 'code' => 'SYNTHETIC_RULE', 'name' => 'SYNTHETIC rule', 'reason_code' => 'SYNTHETIC_REASON',
      'queue_id' => '51', 'timing' => 'call_end', 'active' => true, 'scope' => scope,
      'conditions' => { 'outcome_codes' => [] }, 'actions' => [{ 'kind' => 'project_task', 'parameters' => task }] }
  end
  let(:document) { { 'version' => 1, 'entries' => [rule] } }

  it 'accepts an explicitly typed stored definition without creating native destination records' do
    result = nil
    expect { result = validator.call(document) }.not_to change(JrcProjects::Task, :count)
    expect(result).to eq(document)
    expect(result.fetch('entries').first.fetch('scope').fetch('business_unit_id')).to be_nil
  end

  it 'preserves an explicitly disabled rule instead of dropping false or activating it' do
    rule['active'] = false
    rule['actions'] = []
    rule['scope']['issuer_company_id'] = nil
    expect(validator.call(document).fetch('entries')).to eq([rule])
    expect(rule.fetch('active')).to be(false)
  end

  it 'accepts explicit outcome conditions only after actual ACW completion' do
    rule['timing'] = 'acw_completed'
    rule['conditions']['outcome_codes'] = %w[SYNTHETIC_A SYNTHETIC_B]
    expect(validator.call(document)).to eq(document)
  end

  it 'rejects outcome conditions for an early action while the outcome is still a mutable draft' do
    rule['conditions']['outcome_codes'] = ['SYNTHETIC_A']
    expect { validator.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_automation_definition')
  end

  [nil, false, [], 'legacy'].each do |malformed|
    it "rejects malformed stored configuration #{malformed.inspect}" do
      expect { validator.call(malformed) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_automation_definition')
    end
  end

  [nil, false, 0, '1', 1.5, 2_147_483_648].each do |revision|
    it "rejects an invalid stored revision #{revision.inspect}" do
      document['version'] = revision
      expect { validator.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_automation_definition')
    end
  end

  [nil, false, 1, '01', '0', '9223372036854775808'].each do |identifier|
    it "rejects an invalid stored source identity #{identifier.inspect}" do
      rule['queue_id'] = identifier
      expect { validator.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_automation_definition')
    end
  end

  it 'rejects duplicate logical rules rather than choosing an arbitrary winner' do
    document['entries'] << rule.deep_dup
    expect { validator.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_automation_definition')
  end

  it 'rejects duplicate destinations that could create the same effect twice' do
    rule['actions'] << rule['actions'].first.deep_dup
    expect { validator.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_automation_definition')
  end

  it 'rejects a destination without a native adapter rather than pretending that it executed' do
    rule['actions'].first['kind'] = 'service_desk'
    expect { validator.call(document) }.to raise_error(JrcContactCenter::OperationError, 'ending_action_destination_unavailable')
  end

  %w[account_id user_id unit_id executor_token].each do |field|
    it "rejects a stored authority override #{field}" do
      rule[field] = '1'
      expect { validator.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_automation_definition')
    end
  end

  it 'rejects an active rule without its explicit issuer scope' do
    scope['issuer_company_id'] = nil
    expect { validator.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_automation_definition')
  end

  it 'rejects an active rule with no configured destination' do
    rule['actions'] = []
    expect { validator.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_automation_definition')
  end

  it 'rejects task references requiring coercion inside an immutable definition' do
    task['project_id'] = 11
    expect { validator.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_automation_definition')
  end

  it 'rejects free-form expressions instead of evaluating them' do
    rule['conditions'] = { 'expression' => 'SYNTHETIC never evaluated' }
    expect { validator.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_automation_definition')
  end

  it 'rejects an unbounded rule document' do
    rule['name'] = 'x' * 262_145
    expect { validator.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_automation_definition')
  end

  it 'rejects mixed noncanonical keys without exposing a sorting exception or accepting a second authority field' do
    document[:account_id] = '1'
    expect { validator.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_automation_definition')
  end

  it 'rejects a NUL in rule metadata before sending the private document to PostgreSQL' do
    rule['name'] = "SYNTHETIC_PRIVATE_7f19\u0000"
    expect { validator.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_automation_definition')
  end
end

require 'rails_helper'

# Shape compatibility only; no execution, activation or permission is granted.
RSpec.describe JrcContactCenter::EndingActions::RuleDefinition do
  let(:task) do
    { 'project_id' => '11', 'due_after_days' => nil,
      'attributes' => { 'title' => 'SYNTHETIC typed follow-up', 'priority' => 'medium',
                        'estimated_minutes' => 0, 'board_column_id' => '12' } }
  end
  let(:scope) do
    { 'queue_scope_version_id' => '31', 'integrity_sha256' => 'a' * 64,
      'unit_id' => '21', 'issuer_company_id' => '41', 'business_unit_id' => nil }
  end
  let(:rule) do
    { 'code' => 'SYNTHETIC_TYPED', 'name' => 'SYNTHETIC typed rule', 'reason_code' => 'SYNTHETIC_REASON',
      'queue_id' => '51', 'timing' => 'call_end', 'active' => true, 'scope' => scope,
      'execution_mode' => 'automatic', 'conditions' => { 'outcome_codes' => [] },
      'actions' => [{ 'kind' => 'project_task', 'parameters' => task }] }
  end
  let(:document) { { 'version' => 1, 'entries' => [rule] } }
  let(:validator) { described_class.new }
  let(:sd_action) do
    { 'kind' => 'service_desk', 'parameters' => { 'unit_id' => '61', 'service_id' => nil,
                                                  'attributes' => { 'title' => 'SYNTHETIC explicit ticket',
                                                                    'status_id' => '62', 'priority_id' => '63' } } }
  end

  it 'preserves a legacy document and its exact JSON without adding an execution schema or mode' do
    rule.delete('execution_mode')
    before = JSON.generate(document)
    expect(validator.call(document)).to eq(document)
    expect(JSON.generate(document)).to eq(before)
    expect(rule).not_to have_key('destination_schema_version')
    expect(rule).not_to have_key('execution_mode')
  end

  it 'does not reinterpret an unsupported historical CRM entry as a newly permitted destination' do
    rule['actions'] = [{ 'kind' => 'crm', 'parameters' => {} }]
    expect { validator.call(document) }.to raise_error(JrcContactCenter::OperationError, 'ending_action_destination_unavailable')
  end

  it 'does not reinterpret an unsupported historical Service Desk entry' do
    rule['actions'] = [sd_action]
    expect { validator.call(document) }.to raise_error(JrcContactCenter::OperationError, 'ending_action_destination_unavailable')
  end

  it 'accepts explicit canonical new destination shapes without creating any business records' do
    rule['destination_schema_version'] = 2
    rule['actions'] += [{ 'kind' => 'crm', 'parameters' => {} }, sd_action]
    result = nil
    expect do
      result = validator.call(document)
    end.not_to(change { [JrcProjects::Task.count, JrcCrm::Lead.count, JrcServiceDesk::Ticket.count] })
    expect(result).to eq(document)
    expect(result.fetch('entries').first.fetch('actions').pluck('kind')).to eq(%w[project_task crm service_desk])
  end

  it 'rejects null, false, string, legacy or floating-point schema markers without coercion' do
    inputs = [nil, false, '2', 1, 2.0, 3].map do |value|
      copy = document.deep_dup
      copy['entries'].first['destination_schema_version'] = value
      copy
    end
    expect(rejection_codes(inputs)).to all(eq('invalid_ending_automation_definition'))
  end

  it 'requires an explicit execution mode for an active new-schema rule' do
    rule['destination_schema_version'] = 2
    rule.delete('execution_mode')
    expect { validator.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_automation_definition')
  end

  it 'retains manual confirmation as a distinct mode without pretending it executed' do
    rule['destination_schema_version'] = 2
    rule['execution_mode'] = 'agent_confirmation'
    mode = nil
    expect do
      mode = validator.call(document).fetch('entries').first.fetch('execution_mode')
    end.not_to change(JrcContactCenter::EndingActionExecution, :count)
    expect(mode).to eq('agent_confirmation')
  end

  it 'keeps an explicitly inactive draft inactive without inferring a missing mode or issuer' do
    rule['destination_schema_version'] = 2
    rule['active'] = false
    rule.delete('execution_mode')
    rule['actions'] = []
    scope['issuer_company_id'] = nil
    expect(validator.call(document)).to eq(document)
    expect(rule.fetch('active')).to be false
    expect(rule).not_to have_key('execution_mode')
  end

  it 'rejects repeated kinds in the same rule instead of allowing duplicate destination effects' do
    rule['destination_schema_version'] = 2
    rule['actions'] = [{ 'kind' => 'crm', 'parameters' => {} }, { 'kind' => 'crm', 'parameters' => {} }]
    expect { validator.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_automation_definition')
  end

  it 'rejects a false action entry rather than silently omitting it' do
    rule['destination_schema_version'] = 2
    rule['actions'] << false
    expect { validator.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_automation_definition')
  end

  it 'does not advertise unsupported Nico or arbitrary external commands as executable destinations' do
    rule['destination_schema_version'] = 2
    rule['actions'] = [{ 'kind' => 'nico', 'parameters' => {} }]
    expect { validator.call(document) }.to raise_error(JrcContactCenter::OperationError, 'ending_action_destination_unavailable')
  end

  it 'rejects supplied customer or actor grants inside a native CRM action' do
    rule['destination_schema_version'] = 2
    inputs = %w[contact_id company_id account_id user_id].map do |field|
      copy = document.deep_dup
      copy['entries'].first['actions'] = [{ 'kind' => 'crm', 'parameters' => { field => '1' } }]
      copy
    end
    expect(rejection_codes(inputs)).to all(eq('invalid_ending_automation_definition'))
  end

  it 'requires canonical stored identifiers without changing their representation during reading' do
    rule['destination_schema_version'] = 2
    rule['actions'] = [sd_action]
    sd_action['parameters']['unit_id'] = 61
    expect { validator.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_automation_definition')
  end

  def rejection_codes(inputs)
    inputs.map do |input|
      validator.call(input)
      'unexpected_acceptance'
    rescue JrcContactCenter::OperationError => e
      e.code
    end
  end
end

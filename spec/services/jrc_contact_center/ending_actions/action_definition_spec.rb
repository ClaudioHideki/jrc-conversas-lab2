require 'rails_helper'

RSpec.describe JrcContactCenter::EndingActions::ActionDefinition do
  let(:task) do
    { 'kind' => 'project_task', 'parameters' => {
      'project_id' => '10', 'due_after_days' => nil,
      'attributes' => { 'title' => 'SYNTHETIC existing task', 'priority' => 'medium',
                        'estimated_minutes' => 0, 'board_column_id' => '20' }
    } }
  end
  let(:service_desk) do
    { 'kind' => 'service_desk', 'parameters' => {
      'unit_id' => '10', 'service_id' => nil, 'attributes' => { 'title' => 'SYNTHETIC scoped ticket' }
    } }
  end

  it 'preserves the exact normalized legacy Project Task definition' do
    previous = JrcContactCenter::EndingActions::TaskDefinition.new.call(task.fetch('parameters'))
    expect(described_class.new.call(task)).to eq('kind' => 'project_task', 'parameters' => previous)
  end

  it 'retains native Project normalization without accepting an actor or account override' do
    task['parameters']['attributes']['account_id'] = '999'
    expect { described_class.new.call(task) }.to raise_error(JrcContactCenter::OperationError)
  end

  it 'permits only the native original-contact Lead operation with no client-owned identity parameters' do
    expect(described_class.new.call('kind' => 'crm', 'parameters' => {})).to eq('kind' => 'crm', 'parameters' => {})
  end

  it 'rejects selecting a CRM owner outside the native original-agent command' do
    expect do
      described_class.new.call('kind' => 'crm', 'parameters' => { 'owner_id' => '99' })
    end.to raise_error(JrcContactCenter::OperationError)
  end

  it 'rejects a caller-selected CRM contact rather than treating it as a grant' do
    expect do
      described_class.new.call('kind' => 'crm', 'parameters' => { 'contact_id' => '99' })
    end.to raise_error(JrcContactCenter::OperationError)
  end

  it 'rejects malformed empty-like CRM parameters' do
    expect do
      described_class.new.call('kind' => 'crm', 'parameters' => false)
    end.to raise_error(JrcContactCenter::OperationError)
  end

  it 'reuses the strict native Service Desk destination shape' do
    previous = JrcContactCenter::EndingActions::ServiceDeskDestinationDefinition.new.call(service_desk.fetch('parameters'))
    expect(described_class.new.call(service_desk)).to eq('kind' => 'service_desk', 'parameters' => previous)
  end

  it 'does not allow Service Desk requester selection to replace captured customer identity' do
    service_desk['parameters']['attributes']['requester_id'] = '99'
    expect { described_class.new.call(service_desk) }.to raise_error(JrcContactCenter::OperationError)
  end

  it 'preserves strict native Service Desk identifiers instead of coercing false' do
    service_desk['parameters']['unit_id'] = false
    expect { described_class.new.call(service_desk) }.to raise_error(JrcContactCenter::OperationError)
  end

  it 'does not mutate a frozen stored historical definition during normalization' do
    previous = task.deep_dup
    task['parameters']['attributes'].freeze
    task['parameters'].freeze
    task.freeze
    expect(described_class.new.call(task)).to eq(previous)
    expect(task).to eq(previous)
  end

  it 'does not activate unsupported destinations by accepting arbitrary kind names' do
    expect do
      described_class.new.call('kind' => 'arbitrary_provider', 'parameters' => {})
    end.to raise_error(JrcContactCenter::OperationError, 'ending_action_destination_unavailable')
  end

  it 'rejects an extra account authority field at the action root' do
    expect do
      described_class.new.call('kind' => 'crm', 'parameters' => {}, 'account_id' => '99')
    end.to raise_error(JrcContactCenter::OperationError)
  end
end

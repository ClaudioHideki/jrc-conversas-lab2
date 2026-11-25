require 'rails_helper'

# Parameter shape only. Native authorization/effect/receipt tests remain required.
RSpec.describe JrcContactCenter::EndingActions::DestinationOperationDefinition do
  let(:command) { described_class.new }
  let(:activity) { { 'activity_type' => 'call', 'title' => 'SYNTHETIC original agent follow-up' } }
  let(:update) do
    { 'ticket_id' => '41', 'expected_lock_version' => 2, 'attributes' => { 'title' => 'SYNTHETIC linked ticket update' } }
  end
  let(:crm_action) { { 'kind' => 'crm', 'parameters' => { 'operation' => 'create_activity', 'parameters' => activity } } }
  let(:sd_action) { { 'kind' => 'service_desk', 'parameters' => { 'operation' => 'update_ticket', 'parameters' => update } } }

  it 'retains the original empty native Lead operation without inferring a different effect' do
    action = { 'kind' => 'crm', 'parameters' => {} }
    expect(command.call(action)).to eq(action)
  end

  it 'retains the existing native Service Desk create shape byte for byte' do
    action = { 'kind' => 'service_desk', 'parameters' => {
      'unit_id' => '61', 'service_id' => nil, 'attributes' => { 'title' => 'SYNTHETIC unchanged ticket creation' }
    } }
    expect(command.call(action)).to eq(action)
  end

  it 'uses the existing Activity definition without accepting a caller, customer or unit' do
    result = nil
    expect { result = command.call(crm_action) }.not_to change(JrcCrm::Activity, :count)
    expect(result).to eq(crm_action)
  end

  it 'uses the existing explicit Ticket update definition without inventing a ticket' do
    result = nil
    expect { result = command.call(sd_action) }.not_to change(JrcServiceDesk::Ticket, :count)
    expect(result).to eq(sd_action)
  end

  it 'does not interpret an explicit false operation as the legacy Lead action' do
    crm_action['parameters']['operation'] = false
    expect { command.call(crm_action) }.to raise_error(JrcContactCenter::OperationError, 'ending_action_destination_unavailable')
  end

  it 'does not interpret an unknown or unsupported opportunity action as an available operation' do
    crm_action['parameters']['operation'] = 'update_opportunity'
    expect { command.call(crm_action) }.to raise_error(JrcContactCenter::OperationError, 'ending_action_destination_unavailable')
  end

  it 'rejects a supplied agent override at the operation wrapper' do
    crm_action['parameters']['user_id'] = '99'
    expect { command.call(crm_action) }.to raise_error(JrcContactCenter::OperationError)
  end

  it 'rejects a supplied contact identity in an Activity payload' do
    activity['contact_id'] = '99'
    expect { command.call(crm_action) }.to raise_error(JrcContactCenter::OperationError)
  end

  it 'rejects supplied lifecycle transitions rather than treating ordinary edit as native status execution' do
    update['attributes']['status_id'] = '99'
    expect { command.call(sd_action) }.to raise_error(JrcContactCenter::OperationError)
  end

  it 'requires the native Ticket optimistic version' do
    update.delete('expected_lock_version')
    expect { command.call(sd_action) }.to raise_error(JrcContactCenter::OperationError)
  end

  it 'does not allow a Ticket operation under the CRM kind' do
    sd_action['kind'] = 'crm'
    expect { command.call(sd_action) }.to raise_error(JrcContactCenter::OperationError, 'ending_action_destination_unavailable')
  end

  it 'does not mutate frozen stored parameters or grant execution while normalizing' do
    previous = crm_action.deep_dup
    activity.freeze
    crm_action['parameters'].freeze
    crm_action.freeze
    expect(command.call(crm_action)).to eq(previous)
    expect(crm_action).to eq(previous)
  end
end

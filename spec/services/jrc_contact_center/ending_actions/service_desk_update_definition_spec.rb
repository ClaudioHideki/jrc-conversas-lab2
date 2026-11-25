require 'rails_helper'

RSpec.describe JrcContactCenter::EndingActions::ServiceDeskUpdateDefinition do
  let(:input) { { 'ticket_id' => '12', 'expected_lock_version' => 0, 'attributes' => { 'title' => 'SYNTHETIC update' } } }
  let(:command) { described_class.new }

  it 'normalizes only native identifiers and optimistic versions without adding identities' do
    result = command.call(input.merge('ticket_id' => 12, 'expected_lock_version' => '2'))
    expect(result).to eq(input.merge('expected_lock_version' => 2))
  end

  it 'preserves the native zero version and explicitly nullable description' do
    result = command.call(input.merge('attributes' => { 'description' => nil }))
    expect(result).to eq(input.merge('attributes' => { 'description' => nil }))
  end

  it 'does not accept caller supplied actors, accounts or operational units' do
    inputs = %w[account_id user_id account_user_id unit_id].map { |key| input.merge(key => '1') }
    expect(rejection_codes(inputs)).to all(eq('invalid_ending_service_desk_update_definition'))
  end

  it 'refuses requester and company reassignment within the update' do
    inputs = %w[requester_id company_id].map { |key| input.merge('attributes' => { key => '1' }) }
    expect(rejection_codes(inputs)).to all(eq('invalid_ending_service_desk_update_definition'))
  end

  it 'rejects false or malformed native IDs and versions rather than dropping them' do
    inputs = [input.merge('ticket_id' => false), input.merge('expected_lock_version' => false),
              input.merge('expected_lock_version' => -1), input.merge('attributes' => { 'priority_id' => false })]
    expect(rejection_codes(inputs)).to all(eq('invalid_ending_service_desk_update_definition'))
  end

  it 'rejects blank titles, NUL text and invalid native field containers' do
    inputs = [{ 'title' => ' ' }, { 'description' => "bad\u0000text" }, { 'service_fields' => false }]
    expect(rejection_codes(inputs.map { |value| input.merge('attributes' => value) })).to all(eq('invalid_ending_service_desk_update_definition'))
  end

  it 'requires an explicit native record version' do
    expect { command.call(input.except('expected_lock_version')) }.to raise_error do |error|
      expect(error.code).to eq('invalid_ending_service_desk_update_definition')
    end
  end

  it 'refuses an empty update instead of inventing a native change' do
    expect { command.call(input.merge('attributes' => {})) }.to raise_error do |error|
      expect(error.code).to eq('invalid_ending_service_desk_update_definition')
    end
  end

  it 'does not use ordinary edits to bypass lifecycle or assignment commands' do
    inputs = %w[status_id assignee_account_user_id team_id queue_id].map { |key| input.merge('attributes' => { key => '1' }) }
    expect(rejection_codes(inputs)).to all(eq('invalid_ending_service_desk_update_definition'))
  end

  it 'enforces the bounded configuration payload' do
    expect { command.call(input.merge('attributes' => { 'description' => 'x' * 262_144 })) }.to raise_error do |error|
      expect(error.code).to eq('invalid_ending_service_desk_update_definition')
    end
  end

  def rejection_codes(inputs)
    inputs.map do |value|
      command.call(value)
      'unexpected_acceptance'
    rescue JrcContactCenter::OperationError => e
      e.code
    end
  end
end

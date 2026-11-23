require 'rails_helper'

# Prepared, not executed or applied. Schema acceptance never authorizes a native project or destination.
RSpec.describe JrcContactCenter::EndingActions::TaskDefinition do
  let(:parameters) do
    { 'project_id' => '11', 'due_after_days' => nil, 'attributes' => {
      'title' => 'SYNTHETIC configured follow-up', 'priority' => 'medium', 'estimated_minutes' => 0, 'board_column_id' => '12'
    } }
  end

  it 'preserves explicit literal values without creating a task or copying attendance content' do
    result = nil
    expect { result = described_class.new.call(parameters) }.not_to change(JrcProjects::Task, :count)
    expect(result).to eq(parameters)
    expect(result.fetch('attributes')).not_to have_key('assignee_id')
  end

  it 'preserves an explicit zero-day offset and zero estimated minutes instead of treating them as absent' do
    parameters['due_after_days'] = 0
    result = described_class.new.call(parameters)
    expect(result.fetch('due_after_days')).to eq(0)
    expect(result.fetch('attributes').fetch('estimated_minutes')).to eq(0)
  end

  it 'normalizes only canonical positive integer references, retaining an explicit unassigned native task' do
    parameters['project_id'] = 11
    parameters['attributes']['board_column_id'] = 12
    parameters['attributes']['assignee_id'] = nil
    result = described_class.new.call(parameters)
    expect(result.fetch('project_id')).to eq('11')
    expect(result.fetch('attributes').slice('board_column_id', 'assignee_id')).to eq('board_column_id' => '12', 'assignee_id' => nil)
  end

  [nil, false, [], 0].each do |malformed|
    it "rejects malformed task configuration #{malformed.inspect}" do
      expect { described_class.new.call(malformed) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_task_parameters')
    end
  end

  %w[account_id user_id unit_id].each do |field|
    it "rejects an injected authority field #{field} instead of interpreting it as a grant" do
      parameters[field] = '1'
      expect { described_class.new.call(parameters) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_task_parameters')
    end
  end

  [nil, false, '01', '0', 0, 1.5, '9223372036854775808'].each do |identifier|
    it "rejects an invalid project identity #{identifier.inspect}" do
      parameters['project_id'] = identifier
      expect { described_class.new.call(parameters) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_task_parameters')
    end
  end

  it 'rejects ambiguous absolute and relative deadlines' do
    parameters['due_after_days'] = 0
    parameters['attributes']['due_on'] = '2026-11-23'
    expect { described_class.new.call(parameters) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_task_parameters')
  end

  it 'rejects a missing board-column choice instead of selecting an implicit native destination' do
    parameters['attributes'].delete('board_column_id')
    expect { described_class.new.call(parameters) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_task_parameters')
  end

  it 'rejects unsupported native status and source payload fields' do
    parameters['attributes']['status'] = 'completed'
    parameters['attributes']['call_notes'] = 'SYNTHETIC never transferred'
    expect { described_class.new.call(parameters) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_task_parameters')
  end

  it 'rejects impossible calendar dates instead of correcting them silently' do
    parameters['attributes']['due_on'] = '2026-02-30'
    expect { described_class.new.call(parameters) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_task_parameters')
  end

  it 'rejects deadlines before an explicit start date' do
    parameters['attributes'].merge!('starts_on' => '2026-11-24', 'due_on' => '2026-11-23')
    expect { described_class.new.call(parameters) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_task_parameters')
  end

  %w[title description].each do |field|
    it "rejects a NUL in #{field} before PostgreSQL can echo a private fragment in an encoding error" do
      parameters['attributes'][field] = "SYNTHETIC_PRIVATE_7f19\u0000"
      expect { described_class.new.call(parameters) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_task_parameters')
    end
  end

  it 'rejects invalid UTF8 before serializing or persisting a private task template' do
    parameters['attributes']['title'] = "SYNTHETIC_PRIVATE_7f19\xff".force_encoding(Encoding::UTF_8)
    expect { described_class.new.call(parameters) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_task_parameters')
  end
end

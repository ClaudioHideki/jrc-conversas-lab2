# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcContactCenter::RecordingPolicyDraft do
  let(:definition) { { 'mode' => 'automatic', 'queue_scope' => 'unit', 'queue_ids' => [], 'notice' => '', 'retention_days' => nil } }

  it 'retains an explicitly selected mode without guessing retention or a customer notice' do
    expect(described_class.parse(definition)).to eq(definition.merge('schema_version' => 1))
  end

  it 'normalizes selected native queue identifiers without inventing or duplicating queues' do
    input = definition.merge('mode' => 'on_demand', 'queue_scope' => 'selected_queues', 'queue_ids' => ['12', 2, '2'])
    expect(described_class.parse(input)).to include('queue_ids' => %w[2 12], 'mode' => 'on_demand')
  end

  [nil, false, [], 'draft', { 'mode' => 'automatic' }].each do |value|
    it "rejects the malformed policy document #{value.inspect}" do
      expect { described_class.parse(value) }.to raise_error(JrcContactCenter::OperationError, described_class::ERROR)
    end
  end

  [false, 0, -1, 1.5, '30', 9_007_199_254_740_992].each do |value|
    it "rejects ambiguous or unsafe retention #{value.inspect}" do
      expect { described_class.parse(definition.merge('retention_days' => value)) }
        .to raise_error(JrcContactCenter::OperationError, described_class::ERROR)
    end
  end

  [0, -1, '1x', '01', false].each do |value|
    it "uses the strict native identifier validator for #{value.inspect}" do
      input = definition.merge('queue_scope' => 'selected_queues', 'queue_ids' => [value])
      expect { described_class.parse(input) }.to raise_error(ArgumentError)
    end
  end

  it 'requires a nonempty selected-queue scope and an empty whole-unit queue list' do
    expect { described_class.parse(definition.merge('queue_scope' => 'selected_queues')) }
      .to raise_error(JrcContactCenter::OperationError)
    expect { described_class.parse(definition.merge('queue_ids' => ['1'])) }.to raise_error(JrcContactCenter::OperationError)
  end

  it 'rejects unknown fields, unsupported modes and excessive notice text' do
    expect { described_class.parse(definition.merge('account_id' => 1)) }.to raise_error(JrcContactCenter::OperationError)
    expect { described_class.parse(definition.merge('mode' => 'published')) }.to raise_error(JrcContactCenter::OperationError)
    expect { described_class.parse(definition.merge('notice' => 'x' * 1001)) }.to raise_error(JrcContactCenter::OperationError)
  end

  it 'keeps false stored state distinguishable from a policy that has never been configured' do
    unit = JrcContactCenter::Unit.new(settings: { described_class::KEY => false })
    expect { described_class.stored(unit) }.to raise_error(JrcContactCenter::OperationError, described_class::ERROR)
    unit.settings = {}
    expect(described_class.stored(unit)).to be_nil
  end

  it 'filters the entire typed draft from native request parameter logs' do
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter('recording_policy_draft' => definition)
    expect(filtered).to eq('recording_policy_draft' => '[FILTERED]')
  end

  it 'records notice integrity without persisting the full notice in audit snapshots' do
    value = described_class.parse(definition.merge('notice' => 'SYNTHETIC private notice', 'retention_days' => 37))
    snapshot = described_class.audit_snapshot(value)
    expect(snapshot).to include('notice_present' => true, 'notice_sha256' => Digest::SHA256.hexdigest(value.fetch('notice')),
                                'retention_days' => 37)
    expect(snapshot).not_to have_key('notice')
  end
end

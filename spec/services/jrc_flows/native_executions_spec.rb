require 'spec_helper'
require_relative '../../../app/services/jrc_flows/native_editor_operation'
RSpec.describe 'Native execution inspection policy' do
  let(:root) { '11111111-1111-4111-8111-111111111111' }
  let(:execution) { '22222222-2222-4222-8222-222222222222' }
  let(:period) { { 'from' => '2030-01-01T00:00:00.000Z', 'to' => '2030-01-02T00:00:00.000Z' } }
  it 'requires the explicit execution capability and encodes a bounded period' do
    op = JrcFlows::NativeEditorOperation.resolve!('executions', id: root, query: period)
    expect(op.scope).to eq('flow:executions:read')
    expect(op.method).to eq(:get)
    expect(op.path).to eq("/v1/delegated-flows/#{root}/executions?#{URI.encode_www_form(period.sort)}")
    expect(op.response_limit).to eq(2_200_000)
    detail = JrcFlows::NativeEditorOperation.resolve!('execution', id: root, target_id: execution)
    expect(detail.path).to eq("/v1/delegated-flows/#{root}/executions/#{execution}")
    expect(detail.scope).to eq('flow:executions:read')
  end
  it 'rejects tenant injection, missing periods, overlong periods, duplicate authority and unbounded pages' do
    [period.merge('organizationId' => root), {}, period.merge('to' => '2031-01-01T00:00:00.000Z'), period.merge('pageSize' => '101')].each do |query|
      expect { JrcFlows::NativeEditorOperation.resolve!('executions', id: root, query: query) }.to raise_error(JrcFlows::NativeEditorOperation::Invalid)
    end
    expect { JrcFlows::NativeEditorOperation.resolve!('execution', id: root, target_id: '../other') }.to raise_error(JrcFlows::NativeEditorOperation::Invalid)
    expect { JrcFlows::NativeEditorOperation.resolve!('get', id: root, query: period) }.to raise_error(JrcFlows::NativeEditorOperation::Invalid)
  end
end

require 'rails_helper'

RSpec.describe JrcApprovals::Conditions do
  let(:schema) do
    { 'cents' => 'integer', 'quantity' => 'decimal', 'label' => 'string', 'active' => 'boolean', 'price' => 'money', 'at' => 'datetime' }
  end
  let(:engine) { described_class.new(schema) }

  it 'compares integer cents exactly and respects equality and ranges' do
    expect(engine.match?({ 'field' => 'cents', 'op' => 'lt', 'value' => 100 }, 'cents' => 99)).to be(true)
    expect(engine.match?({ 'field' => 'cents', 'op' => 'lt', 'value' => 100 }, 'cents' => 100)).to be(false)
    expect(engine.match?({ 'field' => 'cents', 'op' => 'between', 'value' => [99, 100] }, 'cents' => 100)).to be(true)
  end

  it 'uses exact decimal strings, finite operators and bounded composition' do
    node = { 'all' => [{ 'field' => 'quantity', 'op' => 'eq', 'value' => '0.10' },
                       { 'any' => [{ 'field' => 'active', 'op' => 'eq', 'value' => true }, { 'const' => false }] }] }
    expect(engine.match?(node, 'quantity' => '0.1', 'active' => true)).to be(true)
    expect(engine.match?(node, 'quantity' => '0.10000000000000000001', 'active' => true)).to be(false)
  end

  it 'supports only declared strings and datetime timezone-aware comparisons' do
    expect(engine.match?({ 'field' => 'label', 'op' => 'contains', 'value' => 'abc' }, 'label' => 'zabc')).to be(true)
    expect(engine.match?({ 'field' => 'label', 'op' => 'in', 'value' => %w[a b] }, 'label' => 'b')).to be(true)
    expect(engine.match?({ 'field' => 'at', 'op' => 'eq', 'value' => '2026-10-12T12:00:00Z' }, 'at' => '2026-10-12T09:00:00-03:00')).to be(true)
  end

  it 'fails on incompatible currencies or missing context rather than returning authorization' do
    node = { 'field' => 'price', 'op' => 'lt', 'value' => { 'currency' => 'BRL', 'amount_cents' => 100 } }
    expect { engine.match?(node, 'price' => { 'currency' => 'USD', 'amount_cents' => 99 }) }
      .to raise_error(JrcApprovals::Error, 'INCOMPATIBLE_CURRENCY')
    expect { engine.match?(node, {}) }.to raise_error(JrcApprovals::Error, 'MISSING_CONTEXT')
  end

  [0.1, Float::INFINITY, 'NaN', nil].each do |value|
    it "rejects non-exact decimal #{value.inspect}" do
      expect { described_class.value!('decimal', value) }.to raise_error(JrcApprovals::Error)
    end
  end

  [{ 'eval' => 'system' }, { 'field' => 'secret', 'op' => 'eq', 'value' => 1 },
   { 'field' => 'cents', 'op' => 'sql', 'value' => 1 }, { 'all' => [] },
   { 'field' => 'cents', 'op' => 'between', 'value' => [3, 1] }].each do |node|
    it "rejects unsupported condition #{node.inspect}" do
      expect { engine.validate!(node) }.to raise_error(JrcApprovals::Error)
    end
  end

  it 'rejects excessive depth, oversize payload and duplicate normalized keys without mutating input' do
    node = { 'const' => true }
    6.times { node = { 'all' => [node] } }
    expect { engine.validate!(node) }.to raise_error(JrcApprovals::Error)
    expect { JrcServiceDesk::CanonicalJson.dump('x' => 'a' * 140_000) }.to raise_error(ArgumentError)
    expect { JrcServiceDesk::CanonicalJson.normalize({ 'a' => 1, a: 2 }) }.to raise_error(ArgumentError)
    source = { 'field' => 'quantity', 'op' => 'eq', 'value' => '0.10' }
    original = Marshal.load(Marshal.dump(source))
    engine.match?(source, 'quantity' => '0.1')
    expect(source).to eq(original)
  end
end

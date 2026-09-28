# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk::CanonicalJson do
  it 'canonicalizes key order and symbol keys while preserving array order' do
    expect(described_class.digest(a: 1, b: { c: [2, 3] })).to eq(described_class.digest('b' => { 'c' => [2, 3] }, 'a' => 1))
    expect(described_class.digest(a: [2, 3])).not_to eq(described_class.digest(a: [3, 2]))
  end

  it 'rejects duplicate normalized keys and non-JSON executable objects' do
    expect { described_class.dump(a: 1, 'a' => 2) }.to raise_error(ArgumentError)
    expect { described_class.dump(value: Object.new) }.to raise_error(ArgumentError)
  end

  it 'rejects non-finite numbers, oversized bodies and excessive nesting' do
    expect { described_class.dump(value: Float::NAN) }.to raise_error(ArgumentError)
    expect { described_class.dump(value: Float::INFINITY) }.to raise_error(ArgumentError)
    expect { described_class.dump(value: 'x' * 140_000) }.to raise_error(ArgumentError)
    nested = 30.times.reduce({}) { |value, _| { child: value } }
    expect { described_class.dump(nested) }.to raise_error(ArgumentError)
  end
end

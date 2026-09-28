# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk::Input do
  it 'accepts only positive strict 64-bit identifiers' do
    expect(described_class.id(12)).to eq(12)
    expect(described_class.id('12')).to eq(12)
    [nil, true, false, 0, -1, 1.0, '12x', ' 12', '01', '1 OR 1=1', [], {}, '9223372036854775808'].each do |value|
      expect { described_class.id(value) }.to raise_error(ArgumentError)
    end
  end

  it 'does not accept ownership fields or duplicate normalized keys' do
    expect { described_class.attributes({ account_id: 5 }, ['title']) }.to raise_error(ArgumentError)
    expect { described_class.attributes({ title: 'one', 'title' => 'two' }, ['title']) }.to raise_error(ArgumentError)
  end

  it 'validates idempotency keys without rewriting them' do
    expect(described_class.request_key('request-123')).to eq('request-123')
    ['', ' ' * 3, 'x' * 121, "key\n", nil, 123].each do |value|
      expect { described_class.request_key(value) }.to raise_error(ArgumentError)
    end
  end
end

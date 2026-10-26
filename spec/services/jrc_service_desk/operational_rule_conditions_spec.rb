# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk::OperationalRuleConditions do
  let(:row) do
    { 'key' => 'explicit', 'precedence' => 1, 'match' => {}, 'output' => { 'queue_id' => 1 },
      'conditions' => { 'operator' => 'all', 'groups' => [
        { 'operator' => 'any', 'items' => [{ 'field' => 'impact', 'operator' => 'eq', 'value' => 'wide' },
                                        { 'field' => 'urgency', 'operator' => 'eq', 'value' => 'urgent' }] },
        { 'operator' => 'all', 'items' => [{ 'field' => 'channel_type', 'operator' => 'neq', 'value' => 'Channel::Email' }] }
      ] } }
  end

  it 'evaluates nested AND and OR with the same matcher used by intake' do
    described_class.validate!(row)
    expect(JrcServiceDesk::OperationalRuleMatcher.call([row], { 'impact' => 'wide', 'channel_type' => 'Channel::Api' })).to eq(row)
    expect(JrcServiceDesk::OperationalRuleMatcher.call([row], { 'urgency' => 'urgent', 'channel_type' => 'Channel::Email' })).to be_nil
    expect(JrcServiceDesk::OperationalRuleMatcher.call([row], { 'impact' => 'wide' })).to be_nil
  end

  it 'never treats a missing fact as satisfying a negative predicate' do
    expect(described_class.match?(row, { 'impact' => 'wide' })).to be(false)
  end

  it 'uses native contact/conversation tags without guessing labels' do
    row['conditions'] = { 'operator' => 'all', 'groups' => [{ 'operator' => 'all', 'items' => [{ 'field' => 'label_id', 'operator' => 'eq', 'value' => 3 }] }] }
    expect(described_class.match?(row, { 'label_id' => [2, 3] })).to be(true)
    expect(described_class.match?(row, { 'label_id' => [] })).to be(false)
  end

  it 'honors validity boundaries and disabled state' do
    row.delete('conditions')
    row['valid_from'] = '2026-10-25T09:00:00Z'
    row['valid_until'] = '2026-10-25T10:00:00Z'
    expect(described_class.match?(row, {}, now: Time.iso8601(row['valid_from']))).to be(true)
    expect(described_class.match?(row, {}, now: Time.iso8601(row['valid_until']))).to be(false)
    row['enabled'] = false
    expect(described_class.match?(row, {}, now: Time.iso8601(row['valid_from']))).to be(false)
  end

  it 'applies an IANA calendar with holidays and rejects incomplete weekly configuration' do
    row.delete('conditions')
    row['window'] = { 'timezone' => 'America/Sao_Paulo', 'conditions' => { 'format' => 'jrc-sd-snapshot-calendar-v1',
      'weekly' => (1..7).to_h { |day| [day.to_s, day <= 5 ? [['09:00', '17:00']] : []] }, 'holidays' => ['2026-10-26'], 'exceptions' => {} } }
    described_class.validate!(row)
    expect(described_class.match?(row, {}, now: Time.iso8601('2026-10-26T13:00:00Z'))).to be(false)
    expect(described_class.match?(row, {}, now: Time.iso8601('2026-10-27T13:00:00Z'))).to be(true)
    row['window']['conditions']['weekly'].delete('7')
    expect { described_class.validate!(row) }.to raise_error(ArgumentError)
  end

  it 'rejects empty AND/OR groups rather than creating an implicit global rule' do
    row['conditions']['groups'].first['items'] = []
    expect { described_class.validate!(row) }.to raise_error(ArgumentError)
  end

  it 'audits conflicts conservatively but permits disjoint exact conditions' do
    left = row.except('conditions').merge('match' => { 'priority_id' => 1 })
    right = left.merge('key' => 'second', 'match' => { 'priority_id' => 2 })
    expect(described_class.conflicts([left, right])).to be_empty
    right['match'] = {}
    expect(described_class.conflicts([left, right])).to eq([['explicit', 'second']])
    expect { JrcServiceDesk::OperationalRuleMatcher.call([left, right], { 'priority_id' => 1 }) }.to raise_error(JrcServiceDesk::OperationalRuleMatcher::Ambiguous)
  end
end

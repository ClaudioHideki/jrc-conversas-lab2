require 'rails_helper'

RSpec.describe JrcContactCenter::DeferredPauseInput do
  let(:attributes) do
    { command_id: SecureRandom.uuid, expected_state_version: '0', expected_request_revision: 'a' * 64, reason_code: 'lunch' }
  end

  it 'accepts only bounded native values and keeps the explicit zero state version' do
    values = described_class.call(attributes.merge(queue_id: 12, justification: '  SYNTHETIC note  '))
    expect(values).to include(queue_id: '12', justification: 'SYNTHETIC note', expected_state_version: '0')
    expect(attributes).not_to have_key(:justification)
  end

  [nil, false, [], 'payload'].each do |value|
    it "rejects malformed envelope #{value.inspect}" do
      expect { described_class.call(value) }.to raise_error(JrcContactCenter::OperationError, 'invalid_deferred_pause')
    end
  end

  [{ account_id: 9 }, { account_user_id: 9 }, { unit_id: 9 }, { state: 'applied' }, { actor_user_id: 9 }].each do |extra|
    it "rejects authority or state fields #{extra.keys.inspect}" do
      expect { described_class.call(attributes.merge(extra)) }.to raise_error(JrcContactCenter::OperationError, 'invalid_deferred_pause')
    end
  end

  [nil, [], {}, false, "lunch\0", ' ', 'x' * 101].each do |value|
    it "rejects malformed reason #{value.inspect}" do
      expect { described_class.call(attributes.merge(reason_code: value)) }.to raise_error(JrcContactCenter::OperationError, 'invalid_deferred_pause')
    end
  end

  [nil, [], false, "note\0", 'x' * 1001].each do |value|
    it "rejects malformed justification #{value.inspect}" do
      expect do
        described_class.call(attributes.merge(justification: value))
      end.to raise_error(JrcContactCenter::OperationError, 'invalid_deferred_pause')
    end
  end

  [[], {}, 1.2, -1, '01', '1x', '9223372036854775808'].each do |value|
    it "rejects malformed queue #{value.inspect}" do
      expect { described_class.call(attributes.merge(queue_id: value)) }.to raise_error(JrcContactCenter::OperationError, 'invalid_deferred_pause')
    end
  end

  ['', 'not-a-uuid', nil, []].each do |value|
    it "rejects malformed request identity #{value.inspect}" do
      expect { described_class.call(attributes.merge(command_id: value)) }.to raise_error(JrcContactCenter::OperationError, 'invalid_deferred_pause')
    end
  end

  [nil, 0, [], 'x', '1x'].each do |value|
    it "rejects malformed state version #{value.inspect}" do
      expect do
        described_class.call(attributes.merge(expected_state_version: value))
      end.to raise_error(JrcContactCenter::OperationError, 'invalid_deferred_pause')
    end
  end

  [nil, false, [], {}, 'a' * 63, 'a' * 65, 'A' * 64, "#{'a' * 64}\n"].each do |value|
    it "rejects malformed request revision #{value.inspect}" do
      expect do
        described_class.call(attributes.merge(expected_request_revision: value))
      end.to raise_error(JrcContactCenter::OperationError, 'invalid_deferred_pause')
    end
  end
end

require 'rails_helper'
require Rails.root.join('script/jrc_call_center_synthetic_password').to_s

RSpec.describe JrcCallCenterSyntheticPassword do
  it 'satisfies the native password policy even when the random part has no digits or lowercase letters' do
    allow(SecureRandom).to receive(:base64).and_call_original
    allow(SecureRandom).to receive(:base64).with(32).and_return('A' * 44)
    weak = User.new(name: 'SYNTHETIC rejected user', email: 'synthetic-rejected@example.test', password: SecureRandom.base64(32))
    expect(weak.valid?).to be(false)
    expect(weak.errors[:password]).not_to be_empty

    user = User.new(name: 'SYNTHETIC valid user', email: 'synthetic-valid@example.test', password: described_class.generate)
    expect(user.valid?).to be(true)
    expect(user.errors[:password]).to be_empty
  end
end

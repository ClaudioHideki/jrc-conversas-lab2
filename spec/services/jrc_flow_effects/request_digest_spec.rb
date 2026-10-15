require 'rails_helper'

RSpec.describe JrcFlowEffects::Request do
  {
    'false' => '0ba96623db057df8ac5aaa2055c4dbcfcdff3a0960fab0dfb289558bad7b94ad',
    '0' => 'b59b4b4563b9ee90c6806650388464ddc445a3d9f2d2ee03fffe6ae8ae627c75',
    '-12.5' => 'f5b70c5595f449aa91a6ad3279a24424b85eccaeafe6aa91cc2069fba804446b',
    '1e3' => '562750c301b65d2edec70ef5071943df1084ce24f0c7570d02586b92e69763ec',
    '"Olá <JRC> 😀\n\"teste\""' => '1de74ee5d911121b80414f23ce3f9d00f131f559e55d9e69f76e460b740f910d'
  }.each do |value, expected|
    it "matches Node SHA256 for #{value}" do
      input = { 'organization_id' => '11111111-2222-4333-8444-555555555555',
                'operation_id' => 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
                'inbox_id' => '2', 'remote_contact_id' => '4', 'expected_control_revision' => '5',
                'operation' => 'note', 'value_json' => value }
      expect(described_class.digest(input, account_id: 1, conversation_id: 3)).to eq(expected)
    end
  end
end

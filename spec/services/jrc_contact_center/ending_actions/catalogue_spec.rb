require 'rails_helper'

# Prepared, not executed. This pure head test does not prove authenticated API or SQL-log privacy.
RSpec.describe JrcContactCenter::EndingActions::Catalogue do
  subject(:catalogue) { described_class.new(account: account) }

  let(:account) { create(:account) }
  let(:rule) do
    { 'code' => 'SYNTHETIC_RULE', 'name' => 'SYNTHETIC rule', 'reason_code' => 'SYNTHETIC_REASON',
      'queue_id' => '51', 'timing' => 'call_end', 'active' => true,
      'scope' => { 'queue_scope_version_id' => '31', 'integrity_sha256' => 'a' * 64,
                   'unit_id' => '21', 'issuer_company_id' => '41', 'business_unit_id' => nil },
      'conditions' => { 'outcome_codes' => [] }, 'actions' => [{ 'kind' => 'project_task', 'parameters' => {
        'project_id' => '11', 'due_after_days' => nil, 'attributes' => {
          'title' => 'SYNTHETIC_PRIVATE_TEMPLATE_7f19', 'priority' => 'medium', 'estimated_minutes' => 0, 'board_column_id' => '12'
        }
      } }] }
  end
  let(:document) { { 'version' => 1, 'entries' => [rule] } }

  it 'puts only revision and a random nonce in the public head without a private template or dictionary-testable definition hash' do
    head = catalogue.head_for(document)
    expect(head.keys.sort).to eq(%w[nonce version])
    expect(head.fetch('version')).to eq(1)
    expect(head.fetch('nonce')).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
    expect(head.to_json).not_to include('SYNTHETIC_PRIVATE_TEMPLATE_7f19', 'project_id', 'definition_sha256')
    expect(catalogue.head_for(document).fetch('nonce')).not_to eq(head.fetch('nonce'))
  end
end

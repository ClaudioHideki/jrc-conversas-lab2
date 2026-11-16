require 'rails_helper'

RSpec.describe Pabx::ScopeMapping, :pabx do
  let(:root) { create(:super_admin) }
  let(:integration) { create(:telephony_integration, pabx_settings: pabx_settings, pabx_username: 'synthetic', pabx_password: 'synthetic') }

  it 'preserves the strict legacy identity contract without accepting another accountcode' do
    mapping = described_class.new(integration)
    expect(mapping.matches?('8')).to be(true)
    expect(mapping.matches?('12')).to be(false)
  end

  it 'accepts explicitly authorized different identifiers without changing the tenant or guessing the CDR identity' do
    row = described_class.authorize(integration: integration, actor: root, accountcode: '12', cdr_identity: 'accountcode')
    integration.update!(pabx_settings: integration.pabx_settings.merge('scope_mapping' => row))
    expect(described_class.new(integration).matches?('12')).to be(true)
    expect(described_class.new(integration).matches?('8')).to be(false)
    expect(described_class.new(integration).cdr_matches?('12')).to be(true)
    expect(integration.reload.pabx_settings['expected_tenant']).to eq('8')
  end

  it 'keeps a separately declared logical tenant in CDR rows' do
    row = described_class.authorize(integration: integration, actor: root, accountcode: '12', cdr_identity: 'tenant')
    integration.update!(pabx_settings: integration.pabx_settings.merge('scope_mapping' => row))
    expect(described_class.new(integration).matches?('12')).to be(true)
    expect(described_class.new(integration).cdr_matches?('8')).to be(true)
    expect(described_class.new(integration).cdr_matches?('12')).to be(false)
  end

  it 'rejects copying an authorization to another Account or changing its tenant' do
    row = described_class.authorize(integration: integration, actor: root, accountcode: '12', cdr_identity: 'accountcode')
    other = create(:telephony_integration, pabx_settings: pabx_settings)
    other.pabx_settings['scope_mapping'] = row
    expect { described_class.new(other).validate! }.to raise_error(Pabx::Error, 'INVALID_SCOPE_MAPPING')
    integration.pabx_settings.merge!('scope_mapping' => row, 'expected_tenant' => '99')
    expect { described_class.new(integration).validate! }.to raise_error(Pabx::Error, 'INVALID_SCOPE_MAPPING')
  end

  it 'rejects authorization by an account administrator and malformed mappings' do
    admin = create(:user, account: integration.account, role: :administrator)
    expect { described_class.authorize(integration: integration, actor: admin, accountcode: '12', cdr_identity: 'tenant') }
      .to raise_error(Pundit::NotAuthorizedError)
    integration.pabx_settings['scope_mapping'] = { 'accountcode' => '12' }
    expect { described_class.new(integration).validate! }.to raise_error(Pabx::Error, 'INVALID_SCOPE_MAPPING')
  end
end

require 'rails_helper'

# Native type/allowlist cases only. Ticket/effect/authorization and contention
# proofs are separate requirements; these examples cannot stand in for them.
RSpec.describe JrcContactCenter::EndingActions::ServiceDeskDestinationDefinition do
  let(:attributes) { { 'title' => 'SYNTHETIC native ticket', 'status_id' => '11', 'priority_id' => '22' } }
  let(:document) { { 'unit_id' => '123', 'service_id' => nil, 'attributes' => attributes } }

  around do |example|
    config = ApplicationRecord.connection_db_config
    databases = %w[jrc_sd_bc_portal_concurrency_20261025_test corporate_gratuity_disposable]
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            databases.include?(ApplicationRecord.connection.current_database)
    raise 'Owned native Service Desk definition runtime required' unless owned

    example.run
  end

  it 'keeps the configured native input and nested service values immutable' do
    document['attributes']['service_fields'] = { 'SYNTHETIC_field' => ['SYNTHETIC answer'] }
    original = document.deep_dup
    result = described_class.new.call(document)
    expect(result).to eq(original)
    result['attributes']['service_fields']['SYNTHETIC_field'] << 'SYNTHETIC later local edit'
    expect(document).to eq(original)
  end

  it 'normalizes native positive identifier types without turning identifiers into permissions' do
    document['unit_id'] = 123
    document['service_id'] = 321
    document['attributes']['status_id'] = 11
    result = described_class.new.call(document)
    expect(result.values_at('unit_id', 'service_id')).to eq(%w[123 321])
    expect(result.fetch('attributes').fetch('status_id')).to eq('11')
  end

  it 'rejects an injected account identifier instead of silently dropping it' do
    document['account_id'] = 999
    expect { described_class.new.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_service_desk_definition')
  end

  it 'rejects an injected actor identifier instead of borrowing that users authority' do
    document['actor_account_user_id'] = 999
    expect { described_class.new.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_service_desk_definition')
  end

  it 'rejects a template requester override because customer identity belongs to the authorized origin' do
    document['attributes']['requester_id'] = '999'
    expect { described_class.new.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_service_desk_definition')
  end

  it 'rejects a template company override instead of interpreting the company identifier as a grant' do
    document['attributes']['company_id'] = '999'
    expect { described_class.new.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_service_desk_definition')
  end

  it 'rejects customer execution flags that could bypass the native employee isolation' do
    document['customer_execution'] = true
    expect { described_class.new.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_service_desk_definition')
  end

  it 'rejects an invented native provider origin enum' do
    document['origin_channel'] = 'call_center'
    expect { described_class.new.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_service_desk_definition')
  end

  it 'rejects a malformed unit identifier through the strict native input validator' do
    document['unit_id'] = '123-untrusted'
    expect { described_class.new.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_service_desk_definition')
  end

  it 'does not discard a false native status identifier as if it had not been configured' do
    document['attributes']['status_id'] = false
    expect { described_class.new.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_service_desk_definition')
  end

  it 'rejects nonpositive native service identifiers' do
    document['service_id'] = -1
    expect { described_class.new.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_service_desk_definition')
  end

  it 'requires an explicit nullable service field in the versioned parameter shape' do
    document.delete('service_id')
    expect { described_class.new.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_service_desk_definition')
  end

  it 'rejects duplicate native keys represented as both strings and symbols' do
    document[:unit_id] = '999'
    expect { described_class.new.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_service_desk_definition')
  end

  it 'rejects blank native titles before preparing a rule for activation' do
    document['attributes']['title'] = '  '
    expect { described_class.new.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_service_desk_definition')
  end

  it 'rejects invalid text bytes before they reach a native SQL binding' do
    document['attributes']['description'] = "SYNTHETIC\u0000invalid"
    expect { described_class.new.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_service_desk_definition')
  end

  it 'retains the existing bounded ending configuration JSON size' do
    document['attributes']['description'] = 'S' * 262_145
    expect { described_class.new.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_service_desk_definition')
  end

  it 'requires native service fields to remain an object rather than an arbitrary scalar' do
    document['attributes']['service_fields'] = false
    expect { described_class.new.call(document) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_service_desk_definition')
  end
end

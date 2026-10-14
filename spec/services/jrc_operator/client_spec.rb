require 'rails_helper'
RSpec.describe JrcOperator::Client do
  let(:binding) { instance_double(JrcOperator::Binding, account_id: 8, company_id: 12, bemtevi_customer_id: '777') }
  let(:config) { { 'btv_origin' => 'https://btv.example.invalid', 'rede_origin' => 'https://rede.example.invalid', 'btv_token_env' => 'JRC_OPERATOR_TEST_BTV', 'rede_token_env' => 'JRC_OPERATOR_TEST_REDE', 'second_copy_verified' => true, 'status_codes' => { 'O' => 'open', 'P' => 'paid' } } }

  around do |example|
    with_modified_env JRC_OPERATOR_ROUTES: { '8:12' => config }.to_json, JRC_OPERATOR_TEST_BTV: 'synthetic-test-only',
                      JRC_OPERATOR_TEST_REDE: 'synthetic-service-token-32-characters' do
      example.run
    end
  end

  it 'passes the documented BTV filter and token server-side without exposing it in inspect' do
    stub_request(:get, 'https://btv.example.invalid/cliente').with(body: { codcliente: 777 }.to_json,
                                                                   headers: { 'token' => 'synthetic-test-only' }).to_return(body: { data: [{
                                                                     cod_cliente: 777, nome: 'Synthetic'
                                                                   }] }.to_json)
    client = described_class.new(binding)
    expect(client.bemtevi('cliente', {}).first['nome']).to eq('Synthetic')
    expect(client.inspect).not_to include('synthetic-test-only')
  end

  it 'keeps unrecognized financial codes unknown and rejects other customers' do
    stub_request(:get,
                 'https://btv.example.invalid/cobrancas').to_return(body: { data: [{ cod_cliente: 777, codcobranca: 44, situacao: 'X' }] }.to_json)
    client = described_class.new(binding)
    expect(client.charges.first['official_status']).to eq('unknown')
    expect { client.collectible!('44') }.to raise_error(JrcOperator::Error, 'CHARGE_NOT_COLLECTIBLE')
    stub_request(:get, 'https://btv.example.invalid/cobrancas').to_return(body: { data: [{ cod_cliente: 778, codcobranca: 44 }] }.to_json)
    expect { client.charges }.to raise_error(JrcOperator::Error, 'CUSTOMER_MISMATCH')
  end

  it 'rejects ambiguous repeated charge rows rather than summing them' do
    stub_request(:get,
                 'https://btv.example.invalid/cobrancas').to_return(body: { data: [{ cod_cliente: 777, codcobranca: 44 },
                                                                                   { cod_cliente: 777, codcobranca: 44 }] }.to_json)
    expect { described_class.new(binding).charges }.to raise_error(JrcOperator::Error, 'AMBIGUOUS_CHARGE')
  end

  it 'never classifies an absent source status using an empty configured code' do
    config['status_codes'][''] = 'paid'
    with_modified_env JRC_OPERATOR_ROUTES: { '8:12' => config }.to_json do
      stub_request(:get, 'https://btv.example.invalid/cobrancas').to_return(body: { data: [{ cod_cliente: 777, codcobranca: 44 }] }.to_json)
      expect(described_class.new(binding).charges.first['official_status']).to eq('unknown')
    end
  end

  it 'accepts only PDF bytes and never follows a second-copy redirect' do
    stub_request(:post, 'https://btv.example.invalid/cobranca/segundaVia').to_return(body: '%PDF-1.4 synthetic',
                                                                                     headers: { 'Content-Type' => 'application/pdf' })
    expect(described_class.new(binding).bemtevi('cobranca/segundaVia', { codcobranca: 44 }, pdf: true)).to start_with('%PDF-')
    stub_request(:post, 'https://btv.example.invalid/cobranca/segundaVia').to_return(status: 302,
                                                                                     headers: { 'Location' => 'https://untrusted.invalid/document' })
    expect { described_class.new(binding).bemtevi('cobranca/segundaVia', {}, pdf: true) }.to raise_error(JrcOperator::Error, 'REMOTE_UNAVAILABLE')
  end

  it 'blocks second copy until its contract is marked verified' do
    config['second_copy_verified'] = false
    with_modified_env JRC_OPERATOR_ROUTES: { '8:12' => config }.to_json do
      expect do
        described_class.new(binding).bemtevi('cobranca/segundaVia', {}, pdf: true)
      end.to raise_error(JrcOperator::Error, 'SECOND_COPY_NOT_VERIFIED')
    end
  end

  it 'does not implement BTV writes or accept credentials in origins' do
    expect { described_class.new(binding).bemtevi('cliente/novo', {}) }.to raise_error(JrcOperator::Error, 'INVALID_ROUTE')
    config['btv_origin'] = 'https://user:secret@btv.example.invalid'
    with_modified_env JRC_OPERATOR_ROUTES: { '8:12' => config }.to_json do
      expect { described_class.new(binding).bemtevi('cliente', {}) }.to raise_error(JrcOperator::Error, 'INVALID_ORIGIN')
    end
  end

  it 'keeps REDE tenant filters in GET queries and credentials outside the payload' do
    request = stub_request(:get, 'https://rede.example.invalid/api/integrations/jrc/v1/ddds')
              .with(query: { account_id: '8', issuer_company_id: '12', external_actor: 'synthetic' },
                    headers: { 'Authorization' => 'Bearer synthetic-service-token-32-characters' })
              .to_return(body: { data: { items: [] } }.to_json)
    expect(described_class.new(binding).rede(:ddds, { 'external_actor' => 'synthetic' })).to eq('items' => [])
    expect(request).to have_been_requested.once
  end

  it 'does not retry a timed out REDE write or change its idempotency key' do
    request = stub_request(:post, 'https://rede.example.invalid/api/integrations/jrc/v1/reservations')
              .with(body: { number_id: 'synthetic', account_id: 8, issuer_company_id: 12 }.to_json,
                    headers: { 'Idempotency-Key' => 'synthetic-timeout-key-001' }).to_raise(Net::ReadTimeout)
    expect do
      described_class.new(binding).rede(:reserve, { 'number_id' => 'synthetic' }, key: 'synthetic-timeout-key-001')
    end.to raise_error(JrcOperator::Error, 'REMOTE_UNAVAILABLE')
    expect(request).to have_been_requested.once
  end

  it 'rejects an oversized second-copy document before storing or sending it' do
    stub_request(:post, 'https://btv.example.invalid/cobranca/segundaVia')
      .to_return(body: "%PDF-#{'x' * 4_000_000}", headers: { 'Content-Type' => 'application/pdf' })
    expect do
      described_class.new(binding).bemtevi('cobranca/segundaVia', { codcobranca: 44 }, pdf: true)
    end.to raise_error(JrcOperator::Error, 'RESPONSE_TOO_LARGE')
  end
end

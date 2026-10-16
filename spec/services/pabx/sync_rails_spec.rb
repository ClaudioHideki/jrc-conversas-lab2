require 'rails_helper'

RSpec.describe 'PABX incremental sync with real PostgreSQL and mocked HTTP', :pabx do
  let(:integration) do
    create(:telephony_integration, pabx_settings: pabx_settings, pabx_username: 'synthetic-user', pabx_password: 'synthetic-password')
  end
  let(:pages) { [{ body: { total: 1, calls: [pabx_row] }.to_json }] }
  let(:endpoint) { 'https://pbx.example.test/api/v1/admin/relatorio-cdr/search' }
  before do
    allow(Resolv).to receive(:getaddresses).with('pbx.example.test').and_return(['93.184.216.34'])
    stub_request(:post, 'https://pbx.example.test/api/v1/auth/login').to_return(body: { token: 'synthetic-token' }.to_json)
    stub_request(:get, 'https://pbx.example.test/api/v1/admin/dashboard-extension').to_return(body: { accountcode: '8' }.to_json)
    stub_request(:post, endpoint).to_return do |request|
      index = JSON.parse(request.body).fetch('page', 1) - 1
      pages.fetch([index, pages.size - 1].min)
    end
  end

  it 'imports multiple pages idempotently and conserves the Account-local cursor on replay' do
    pages.replace([{ body: { total: 2, calls: [pabx_row] }.to_json },
                   { body: { total: 2, calls: [pabx_row(uniqueId: 'second')] }.to_json }])
    2.times { expect(Pabx::Sync.new(integration).call).to eq(2) }
    expect(TelephonyCallRecord.where(account: integration.account).count).to eq(2)
    expect(integration.reload.pabx_sync_state).to include('last_error' => nil, 'imported' => 2)
    expect(integration.pabx_sync_state['cursor']).to be_present
  end

  it 'rolls back a partial import and resumes from the same successful checkpoint after a temporary HTTP failure' do
    cursor = 5.minutes.ago.change(usec: 0).iso8601
    integration.update!(pabx_sync_state: { cursor: cursor })
    pages.replace([{ body: { total: 2, calls: [pabx_row] }.to_json }, { body: '', status: 504 }])
    expect { Pabx::Sync.new(integration).call }.to raise_error(Pabx::Error, 'PROVIDER_ERROR')
    expect(TelephonyCallRecord.where(account: integration.account)).to be_empty
    expect(integration.reload.pabx_sync_state['cursor']).to eq(cursor)
    pages[1] = { body: { total: 2, calls: [pabx_row(uniqueId: 'second')] }.to_json }
    Pabx::Sync.new(integration).call
    expect(TelephonyCallRecord.where(account: integration.account).count).to eq(2)
    expect(integration.reload.pabx_sync_state['last_error']).to be_nil
  end

  it 'rejects empty pages while records are still missing' do
    pages.replace([{ body: { total: 2, calls: [pabx_row] }.to_json }, { body: { total: 2, calls: [] }.to_json }])
    expect { Pabx::Sync.new(integration).call }.to raise_error(Pabx::Error, 'INVALID_PAGINATION')
    expect(TelephonyCallRecord.where(account: integration.account)).to be_empty
    expect(integration.reload.pabx_sync_state).not_to have_key('cursor')
  end

  it 'rejects repeated pages without committing their first copy' do
    pages.replace([{ body: { total: 2, calls: [pabx_row] }.to_json }])
    expect { Pabx::Sync.new(integration).call }.to raise_error(Pabx::Error, 'REPEATED_PAGE')
    expect(TelephonyCallRecord.where(account: integration.account)).to be_empty
  end

  it 'rejects changing totals and preserves a successful checkpoint' do
    cursor = 5.minutes.ago.iso8601
    integration.update!(pabx_sync_state: { cursor: cursor })
    pages.replace([{ body: { total: 2, calls: [pabx_row] }.to_json },
                   { body: { total: 3, calls: [pabx_row(uniqueId: 'second')] }.to_json }])
    expect { Pabx::Sync.new(integration).call }.to raise_error(Pabx::Error, 'INVALID_PAGINATION')
    expect(integration.reload.pabx_sync_state['cursor']).to eq(cursor)
    expect(TelephonyCallRecord.where(account: integration.account)).to be_empty
  end

  it 'rejects an inconsistent reported current page' do
    pages.replace([{ body: { total: 1, calls: [pabx_row], resultado: { current_page: 2 } }.to_json }])
    expect { Pabx::Sync.new(integration).call }.to raise_error(Pabx::Error, 'INVALID_PAGINATION')
    expect(TelephonyCallRecord.where(account: integration.account)).to be_empty
  end

  it 'enforces the real twenty-page limit and rolls back the bounded import' do
    pages.replace(21.times.map { |index| { body: { total: 21, calls: [pabx_row(uniqueId: "page-#{index}")] }.to_json } })
    expect { Pabx::Sync.new(integration).call }.to raise_error(Pabx::Error, 'PAGE_LIMIT_EXCEEDED')
    expect(a_request(:post, endpoint)).to have_been_made.times(20)
    expect(TelephonyCallRecord.where(account: integration.account)).to be_empty
  end

  it 'enforces the wall-clock budget without advancing the cursor' do
    stub_const('Pabx::Sync::MAX_SECONDS', 0)
    expect { Pabx::Sync.new(integration).call }.to raise_error(Pabx::Error, 'TIME_LIMIT_EXCEEDED')
    expect(integration.reload.pabx_sync_state).not_to have_key('cursor')
  end

  ['broken', 10.minutes.from_now.iso8601].each do |cursor|
    it "rejects invalid cursor #{cursor == 'broken' ? 'format' : 'future'} before any API request" do
      integration.update!(pabx_sync_state: { cursor: cursor })
      expect { Pabx::Sync.new(integration).call }.to raise_error(Pabx::Error, 'INVALID_CURSOR')
      expect(a_request(:post, endpoint)).not_to have_been_made
      expect(integration.reload.pabx_sync_state['cursor']).to eq(cursor)
    end
  end

  it 'uses the Client renewal path once after a protected CDR request returns 401' do
    stub_request(:post, endpoint).to_return(status: 401).then.to_return(body: { total: 1, calls: [pabx_row] }.to_json)
    expect(Pabx::Sync.new(integration).call).to eq(1)
    expect(a_request(:post, 'https://pbx.example.test/api/v1/auth/login')).to have_been_made.twice
    expect(a_request(:post, endpoint)).to have_been_made.twice
  end

  [429, 503].each do |status|
    it "persists a sanitized failure after HTTP #{status} without importing data" do
      pages.replace([{ status: status, body: 'synthetic-password synthetic-token' }])
      expect { Pabx::Sync.new(integration).call }.to raise_error(Pabx::Error)
      expect(integration.reload.pabx_sync_state['last_error']).to eq(status == 429 ? 'RATE_LIMITED' : 'PROVIDER_ERROR')
      expect(integration.pabx_sync_state.to_json).not_to include('synthetic-password', 'synthetic-token')
      expect(TelephonyCallRecord.where(account: integration.account)).to be_empty
    end
  end

  it 'keeps pagination pending rather than guessing an undocumented continuation field' do
    integration.update!(pabx_settings: integration.pabx_settings.except('cdr_page_parameter'))
    pages.replace([{ body: { total: 2, calls: [pabx_row] }.to_json }])
    expect { Pabx::Sync.new(integration).call }.to raise_error(Pabx::Error, 'CDR_PAGINATION_PENDING')
    expect(TelephonyCallRecord.where(account: integration.account)).to be_empty
    expect(integration.reload.pabx_sync_state).not_to have_key('cursor')
  end

  it 'catches up an old cursor in bounded contiguous windows rather than skipping the backlog' do
    cursor = 40.days.ago.change(usec: 0)
    integration.update!(pabx_sync_state: { cursor: cursor.iso8601 })
    pages.replace([{ body: { total: 1, calls: [pabx_row(started_at: (cursor - 60.seconds).iso8601)] }.to_json }])
    Pabx::Sync.new(integration).call
    expect(integration.reload.pabx_sync_state['cursor']).to eq((cursor - 120.seconds + 7.days).iso8601)
    expect(Time.iso8601(integration.pabx_sync_state['last_attempt_at'])).to be > 1.minute.ago
  end

  it 'preserves the cursor and a sanitized state after a transport timeout' do
    stub_request(:post, endpoint).to_timeout
    expect { Pabx::Sync.new(integration).call }.to raise_error(Pabx::Error, 'TIMEOUT')
    expect(integration.reload.pabx_sync_state).to include('last_error' => 'TIMEOUT')
    expect(integration.pabx_sync_state).not_to have_key('cursor')
  end

  it 'stops after a second CDR 401 without importing or advancing the cursor' do
    stub_request(:post, endpoint).to_return(status: 401)
    expect { Pabx::Sync.new(integration).call }.to raise_error(Pabx::Error, 'INVALID_CREDENTIALS')
    expect(a_request(:post, endpoint)).to have_been_made.twice
    expect(integration.reload.pabx_sync_state).not_to have_key('cursor')
    expect(TelephonyCallRecord.where(account: integration.account)).to be_empty
  end

  it 'rejects a response exceeding the requested per-page quantity' do
    rows = 21.times.map { |index| pabx_row(uniqueId: "oversized-#{index}") }
    pages.replace([{ body: { total: 21, calls: rows }.to_json }])
    expect { Pabx::Sync.new(integration).call }.to raise_error(Pabx::Error, 'INVALID_PAGINATION')
    expect(TelephonyCallRecord.where(account: integration.account)).to be_empty
  end
end

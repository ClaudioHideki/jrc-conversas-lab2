require 'rails_helper'
require 'database_cleaner/active_record'

RSpec.describe JrcCampaigns::BrokerMessageSender do
  self.use_transactional_tests = false

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }
  let(:delivery) do
    JrcCampaigns::TestDelivery.create!(account: account, inbox: inbox, requested_by: admin, phone_number: '+5511999999000',
                                       idempotency_key: SecureRandom.uuid, payload_digest: 'synthetic-media', status: 'sending')
  end
  let(:url) { 'https://media.example.test/campaign.png' }
  let(:bytes) { Rails.root.join('spec/assets/avatar.png').binread }
  let(:content_type) { 'image/png' }
  let(:step) { { 'kind' => 'image', 'body' => 'Synthetic caption', 'media_url' => url, 'file_name' => 'campaign.png' } }
  let(:arguments) { { delivery: delivery, user: admin, phone_number: delivery.phone_number, step: step, attributes: {} } }
  let(:uploaded_keys) { [] }
  let(:storage) { ActiveStorage::Blob.service }

  around do |example|
    disposable = Rails.env.test? && ActiveRecord::Base.connection.adapter_name == 'PostgreSQL' &&
                 ActiveRecord::Base.connection_db_config.database.end_with?('_test')
    raise 'Disposable PostgreSQL test database required' unless disposable

    DatabaseCleaner.clean_with(:deletion)
    with_modified_env('SAFE_FETCH_ALLOW_PRIVATE_NETWORK' => 'false') { example.run }
  ensure
    clear_enqueued_jobs
    uploaded_keys.each { |key| storage.delete(key) } if disposable
    DatabaseCleaner.clean_with(:deletion) if disposable
  end

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('media.example.test').and_return(['93.184.216.34'])
    stub_request(:get, url).to_return(status: 200, body: bytes, headers: { 'Content-Type' => content_type })
    delivery
    allow(storage).to receive(:upload).and_wrap_original do |original, key, io, **options|
      uploaded_keys << key
      original.call(key, io, **options)
    end
  end

  it 'commits fetched PNG bytes after SafeFetch has removed its real tempfile' do
    message = described_class.call(**arguments)

    expect(message.reload.attachments.sole.file.download).to eq(bytes)
    expect(message.content).to eq('Synthetic caption')
    expect(delivery.reload.metadata['message_id']).to eq(message.id)
    expect(delivery.external_id).to eq("broker:#{account.id}:#{inbox.id}:#{message.id}")
  end

  context 'with a fetched JPEG' do
    let(:bytes) { Rails.root.join('spec/assets/jrc_campaign_static.jpg').binread }
    let(:content_type) { 'image/jpeg' }

    it 'retains the original image bytes through the outer transaction commit' do
      message = described_class.call(**arguments)
      expect(message.reload.attachments.sole.file.download).to eq(bytes)
    end
  end

  context 'with a fetched document' do
    let(:bytes) { 'Synthetic plain text document' }
    let(:content_type) { 'text/plain' }
    let(:step) { { 'kind' => 'document', 'body' => 'Synthetic caption', 'media_url' => url, 'file_name' => 'campaign.txt' } }

    it 'retains document bytes after SafeFetch cleanup' do
      message = described_class.call(**arguments)
      expect(message.reload.attachments.sole.file.download).to eq(bytes)
      expect(message.attachments.sole.file_type).to eq('file')
    end
  end

  it 'does not fetch or upload a second blob when the same delivery is reused' do
    first = described_class.call(**arguments)
    keys = uploaded_keys.dup

    expect(described_class.call(**arguments).id).to eq(first.id)
    expect(uploaded_keys).to eq(keys)
    expect(first.reload.attachments.sole.file.download).to eq(bytes)
  end

  it 'removes uploaded bytes when the later delivery write rolls back' do
    allow(delivery).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(delivery))

    expect { described_class.call(**arguments) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(account.messages).to be_empty
    expect(ActiveStorage::Blob.count).to eq(0)
    expect(uploaded_keys).not_to be_empty
    expect(uploaded_keys.none? { |key| storage.exist?(key) }).to be(true)
    expect(delivery.reload.metadata).not_to have_key('message_id')
  end

  it 'removes a partially uploaded object when storage raises after writing bytes' do
    allow(storage).to receive(:upload).and_wrap_original do |original, key, io, **options|
      uploaded_keys << key
      original.call(key, io, **options)
      raise IOError, 'Synthetic upload failure'
    end

    expect { described_class.call(**arguments) }.to raise_error(IOError, 'Synthetic upload failure')
    expect(account.messages).to be_empty
    expect(ActiveStorage::Blob.count).to eq(0)
    expect(uploaded_keys).not_to be_empty
    expect(uploaded_keys.none? { |key| storage.exist?(key) }).to be(true)
    expect(delivery.reload.metadata).not_to have_key('message_id')
  end

  it 'removes newly uploaded bytes if the enclosing caller transaction rolls back' do
    account.with_lock do
      described_class.call(**arguments)
      raise ActiveRecord::Rollback
    end

    expect(account.messages).to be_empty
    expect(ActiveStorage::Blob.count).to eq(0)
    expect(uploaded_keys).not_to be_empty
    expect(uploaded_keys.none? { |key| storage.exist?(key) }).to be(true)
    expect(delivery.reload.metadata).not_to have_key('message_id')
  end

  it 'retains committed media when a message after-commit callback raises' do
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original
    allow(Rails.configuration.dispatcher).to receive(:dispatch).with('message.created', anything, anything).and_raise('Synthetic callback failure')

    expect { described_class.call(**arguments) }.to raise_error('Synthetic callback failure')
    message = account.messages.find(delivery.reload.metadata.fetch('message_id'))
    expect(message.attachments.sole.file.download).to eq(bytes)
    expect(uploaded_keys.all? { |key| storage.exist?(key) }).to be(true)
  end

  context 'with fetched WebP' do
    let(:bytes) { Rails.root.join('spec/assets/jrc_campaign_static.webp').binread }
    let(:content_type) { 'image/webp' }

    it 'keeps normalization when committing the fetched image' do
      message = described_class.call(**arguments)
      expect(message.attachments.sole.file.content_type).to eq('image/png')
      expect(message.attachments.sole.file.download).to start_with("\x89PNG\r\n\x1A\n".b)
    end
  end

  it 'still rejects private destination addresses' do
    allow(Resolv).to receive(:getaddresses).with('media.example.test').and_return(['127.0.0.1'])

    expect { described_class.call(**arguments) }.to raise_error(ArgumentError, /mídia pública/)
    expect(account.messages).to be_empty
    expect(uploaded_keys).to be_empty
  end

  it 'still rejects a mismatched response MIME before upload' do
    stub_request(:get, url).to_return(status: 200, body: bytes, headers: { 'Content-Type' => 'text/html' })

    expect { described_class.call(**arguments) }.to raise_error(ArgumentError, /mídia pública/)
    expect(account.messages).to be_empty
    expect(uploaded_keys).to be_empty
  end

  it 'still rejects more than 10 MB before creating an attachment' do
    stub_request(:get, url).to_return(status: 200, body: 'x' * (10.megabytes + 1), headers: { 'Content-Type' => content_type })

    expect { described_class.call(**arguments) }.to raise_error(ArgumentError, /mídia pública/)
    expect(account.messages).to be_empty
    expect(uploaded_keys).to be_empty
  end
end

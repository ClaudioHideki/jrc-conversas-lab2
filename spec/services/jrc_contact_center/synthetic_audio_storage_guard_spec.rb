require 'rails_helper'
require Rails.root.join('script/jrc_call_center_audio_storage_guard')

RSpec.describe JrcContactCenter::SyntheticAudioStorageGuard do
  it 'accepts only the actual explicitly owned CI database, Redis15 and native local test storage' do
    expect { described_class.call }.not_to raise_error
  end

  it 'rejects an unowned runner environment before reaching its storage service' do
    with_modified_env RUNNER_ENVIRONMENT: 'self-hosted' do
      expect(ActiveStorage::Blob).not_to receive(:service)
      expect { described_class.call }.to raise_error(RuntimeError, /Exclusive synthetic audio database/)
    end
  end

  it 'does not connect to or accept an external Redis locator' do
    with_modified_env REDIS_URL: 'redis://not-owned.example.test:6379/15' do
      expect(ActiveStorage::Blob).not_to receive(:service)
      expect { described_class.call }.to raise_error(RuntimeError, /Exclusive synthetic audio database/)
    end
  end

  it 'rejects a cloud-like alternative instead of selecting a fallback service' do
    allow(ActiveStorage::Blob).to receive(:service).and_return(Object.new)
    expect { described_class.call }.to raise_error(RuntimeError, /own local disk storage/)
  end

  it 'rejects even a local disk rooted outside the owned storage directories without writing any file there' do
    service = ActiveStorage::Blob.service
    allow(service).to receive(:root).and_return(Rails.root.join('config').to_s)
    expect { described_class.call }.to raise_error(RuntimeError, /own local disk storage/)
  end
end

require 'rails_helper'
require 'socket'

RSpec.describe 'Authorized scanning of imported media', type: :request do
  include_context 'JRC migration media fixtures'
  let(:blob) { execute_media }
  let(:scan_path) { "/api/v1/accounts/#{account.id}/jrc_migration_batches/#{batch.id}/items/#{batch.items.sole.id}/scan" }
  let(:download_path) { Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true) }

  # Run the real INSTREAM adapter and verify every byte. Only the daemon and
  # its read-only /run socket endpoint are replaced with a test-owned server.
  def with_scanner(reply, after_io: nil)
    path = "/tmp/jrc-migration-scan-#{SecureRandom.hex(5)}.sock"
    received = +''.b
    server = UNIXServer.new(path)
    worker = Thread.new do
      client = server.accept
      raise 'Bad scanner command' unless client.read(10) == "zINSTREAM\0"

      loop do
        length = client.read(4).unpack1('N')
        break if length.zero?

        received << client.read(length)
      end
      client.write(reply)
      client.close
    end
    allow(UNIXSocket).to receive(:open).with('/run/jrc-migration-test-clam.sock') do |&operation|
      client = UNIXSocket.new(path)
      begin
        value = operation.call(client)
        after_io&.call
        value
      ensure
        client.close
      end
    end
    with_modified_env JRC_SD_CLAMAV_SOCKET: '/run/jrc-migration-test-clam.sock' do
      yield
    end
    expect(worker.join(1)).not_to be_nil
    worker.value
    expect(received).to eq(bytes)
  ensure
    worker&.kill if worker&.alive?
    worker&.join
    server&.close
    File.unlink(path) if path && File.exist?(path)
  end

  def scan
    post scan_path, headers: admin.create_new_auth_token
  end

  it 'releases only source bytes verified through the configured scanner and audits the authorized operation' do
    get download_path, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    with_scanner("stream: OK\0") { scan }
    expect(response).to have_http_status(:ok)
    expect(blob.reload.metadata).to include('service_desk_scan_state' => 'clean', 'service_desk_scan_sha256' => media_row['file_sha256'])
    expect(batch.events.where(action: 'MEDIA_SCANNED').sole.metadata).to include('scan_state' => 'clean')
    expect(response.body).not_to include(blob.key, 'file_base64', 'storage_key', 'claim_token')
    get download_path, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq(bytes)
  end

  it 'keeps infected and unavailable verdicts blocked without fabricating scan success' do
    blob
    with_scanner("stream: Synthetic-Test-Signature FOUND\0") { scan }
    expect(response).to have_http_status(:ok)
    expect(blob.reload.metadata['service_desk_scan_state']).to eq('infected')
    get download_path, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    with_modified_env(JRC_SD_CLAMAV_SOCKET: nil) { scan }
    expect(response).to have_http_status(:ok)
    expect(blob.reload.metadata['service_desk_scan_state']).to eq('unavailable')
  end

  it 'denies a current non-administrator before invoking the scanner' do
    blob
    account.account_users.find_by!(user: admin).update!(role: :agent)
    expect(JrcServiceDesk::AttachmentScanner).not_to receive(:new)
    scan
    expect(response).to have_http_status(:forbidden)
  end

  it 'revalidates revoked authority after the local scan before persisting a release' do
    blob
    revoke = -> { account.account_users.find_by!(user: admin).update!(role: :agent) }
    with_scanner("stream: OK\0", after_io: revoke) { scan }
    expect(response).to have_http_status(:forbidden)
    expect(blob.reload.metadata['service_desk_scan_state']).to eq('unavailable')
  end

  it 'rejects storage changed during scanning rather than releasing the stale clean result' do
    blob
    tamper = -> { blob.service.upload(blob.key, StringIO.new('Synthetic changed bytes')) }
    with_scanner("stream: OK\0", after_io: tamper) { scan }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(blob.reload.metadata['service_desk_scan_state']).to eq('unavailable')
    get download_path, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end
end

require 'rails_helper'
require 'zip'
require 'stringio'

RSpec.describe JrcContactCenter::AudioArchives do
  include_context 'with an institutional audio receipt'

  let(:access) { JrcContactCenter::AudioLibraryAccess.new(context: context) }
  let(:versions) do
    Array.new(2) do |index|
      JrcContactCenter::AudioUploads.new(access: access).create!(
        unit_id: unit.id, attributes: { name: "SYNTHETIC selected audio #{index}" }, file: upload, key: "synthetic-archive-source-#{index}"
      )
    end
  end
  let(:items) do
    versions.map do |version|
      { 'audio_asset_id' => version.audio_asset_id.to_s, 'audio_version_id' => version.id.to_s,
        'inspection_id' => version.reload.latest_inspection.id.to_s, 'sha256' => version.sha256 }
    end
  end
  let(:archives) { described_class.new(context: context) }

  it 'returns a bounded private ZIP with independently named exact bytes and a manifest without storage locators' do
    request = items
    original = versions.map(&:attributes)
    result = archives.call(items: request)
    expect([result.account_id, result.unit_id, result.entry_count]).to eq([account.id.to_s, unit.id.to_s, 2])
    expect(Digest::SHA256.hexdigest(result.bytes)).to eq(result.sha256)
    expect(result.selection_sha256).to eq(Digest::SHA256.hexdigest(JSON.generate(request.map { |row| row.sort.to_h })))
    Zip::File.open_buffer(StringIO.new(result.bytes)) do |archive|
      manifest = JSON.parse(archive.read('manifesto.json'))
      expect(archive.entries.map(&:name).uniq.length).to eq(3)
      expect(manifest.fetch('items').map { |entry| Digest::SHA256.hexdigest(archive.read(entry.fetch('archive_name'))) })
        .to eq(versions.map(&:sha256))
      expect(manifest.to_json).not_to match(/blob_id|signed_id|service_url|idempotency_key|input_digest/)
    end
    expect(versions.map { |version| version.reload.attributes }).to eq(original)
  end

  it 'rejects duplicate source/version selections rather than relying on archive overwrite behavior' do
    request = [items.first, items.first.dup]
    expect { archives.call(items: request) }.to raise_error(JrcContactCenter::OperationError, 'invalid_institutional_audio_archive')
    expect(JrcContactCenter::AudioVersion.where(account: account).count).to eq(2)
  end

  it 'rejects empty, scalar and oversized selections before reading any source bytes' do
    allow(JrcContactCenter::AudioBytes).to receive(:new).and_raise('No read is allowed for a malformed archive request')
    [[], false, nil, {}, Array.new(21, {})].each do |request|
      expect { archives.call(items: request) }.to raise_error(JrcContactCenter::OperationError, 'invalid_institutional_audio_archive')
    end
  end

  it 'refuses actor, account, unit or storage locator fields inside a selected item' do
    request = items.first
    %w[user_id account_id unit_id blob_id signed_id].each do |field|
      expect { archives.call(items: [request.merge(field => '999')]) }
        .to raise_error(JrcContactCenter::OperationError, 'invalid_institutional_audio_archive')
    end
  end

  it 'enforces the aggregate bound before any actual byte release' do
    request = items
    allow(JrcContactCenter::AudioArchiveInput).to receive(:limits).and_return(max_entries: 20, max_bytes: bytes.bytesize)
    allow(JrcContactCenter::AudioBytes).to receive(:new).and_raise('Aggregate admission must happen before byte reads')
    expect { archives.call(items: request) }.to raise_error(JrcContactCenter::OperationError, 'institutional_audio_archive_limit_exceeded')
    expect(versions.map { |version| version.reload.blob.download }).to eq([bytes, bytes])
  end

  it 'does not use an inspection ID or digest as an authority grant or a replacement for current verification' do
    request = items
    request = [request.first.merge('inspection_id' => '9223372036854775807')]
    expect { archives.call(items: request) }.to raise_error(JrcContactCenter::OperationError, 'institutional_audio_archive_source_changed')
    expect(JrcContactCenter::AudioVersion.where(account: account).count).to eq(2)
  end

  it 'rejects a genuine version attached to a different source asset' do
    request = items
    invalid = request.first.merge('audio_version_id' => request.last.fetch('audio_version_id'))
    expect { archives.call(items: [invalid]) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'never exposes a source in a denied native unit even with a known valid version identifier' do
    request = items
    hidden = JrcContactCenter::AudioAsset.create!(account: account, unit: units.last, name: 'SYNTHETIC denied archive source')
    invalid = request.first.merge('audio_asset_id' => hidden.id.to_s)
    expect { archives.call(items: [invalid]) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(versions.map { |version| version.reload.blob.download }).to eq([bytes, bytes])
  end

  it 'withholds the complete archive after a profile withdrawal during native ZIP generation' do
    request = items
    allow(archives).to receive(:archive_bytes).and_wrap_original do |original, *arguments|
      payload = original.call(*arguments)
      member.custom_role.update!(permissions: %w[jrc_contact_center_view])
      payload
    end
    expect { archives.call(items: request) }.to raise_error(Pundit::NotAuthorizedError)
    expect(versions.map { |version| version.reload.blob.download }).to eq([bytes, bytes])
  end

  it 'withholds an archive when the exact selected proof is superseded before final authorization' do
    request = items
    allow(archives).to receive(:archive_bytes).and_wrap_original do |original, *arguments|
      payload = original.call(*arguments)
      first = versions.first
      JrcContactCenter::AudioInspections.new(access: access).create!(
        asset_id: first.audio_asset_id, version_id: first.id, key: 'synthetic-archive-new-proof-0001'
      )
      payload
    end
    expect { archives.call(items: request) }.to raise_error(JrcContactCenter::OperationError, 'institutional_audio_archive_source_changed')
    expect(versions.first.reload.latest_inspection).to be_ready
  end

  it 'does not substitute unverified or corrupted bytes inside an otherwise valid selection' do
    request = items
    source = versions.last
    source.blob.service.upload(source.blob.key, StringIO.new('SYNTHETIC corrupted source bytes'))
    expect { archives.call(items: request) }.to raise_error(JrcContactCenter::OperationError, 'institutional_audio_integrity_failed')
    expect(JrcContactCenter::AudioVersion.where(account: account).count).to eq(2)
  end

  it 'does not fall back to a previous clean proof when a newer actual inspection is unavailable' do
    request = items
    first = versions.first
    with_modified_env JRC_CC_AUDIO_CLAMAV_SOCKET: nil do
      JrcContactCenter::AudioInspections.new(access: access).create!(
        asset_id: first.audio_asset_id, version_id: first.id, key: 'synthetic-archive-unavailable-0001'
      )
    end
    expect { archives.call(items: request) }.to raise_error(JrcContactCenter::OperationError, 'institutional_audio_not_verified')
    expect(Audited.audit_class.where(auditable: first, action: 'read')).to be_empty
  end

  it 'keeps even two individually authorized native units out of the same archive' do
    request = items
    business_unit_id = units.last.settings.fetch('business_unit_id')
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: company,
                                                business_unit_id: business_unit_id, active: true, structure_managed: true)
    other = JrcContactCenter::AudioUploads.new(access: access).create!(
      unit_id: units.last.id, attributes: { name: 'SYNTHETIC other allowed unit' }, file: upload, key: 'synthetic-archive-other-unit-0001'
    )
    request << { 'audio_asset_id' => other.audio_asset_id.to_s, 'audio_version_id' => other.id.to_s,
                 'inspection_id' => other.reload.latest_inspection.id.to_s, 'sha256' => other.sha256 }
    expect { archives.call(items: request) }.to raise_error(JrcContactCenter::OperationError, 'institutional_audio_archive_limit_exceeded')
    expect(Audited.audit_class.where(auditable: versions, action: 'read')).to be_empty
  end
end

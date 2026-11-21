require 'rails_helper'

RSpec.describe JrcContactCenter::AudioAssetMoves do
  include_context 'with an institutional audio receipt'

  let(:library) { JrcContactCenter::AudioLibraryAccess.new(context: context) }
  let(:assets) do
    Array.new(2) { |index| JrcContactCenter::AudioAsset.create!(account: account, unit: unit, name: "SYNTHETIC move source #{index}") }
  end
  let(:folder) { JrcContactCenter::AudioFolder.create!(account: account, unit: unit, name: 'SYNTHETIC selected destination') }
  let(:items) { assets.map { |record| move_descriptor(record) } }

  def move_descriptor(record)
    { 'audio_asset_id' => record.id.to_s, 'expected_revision' => JrcContactCenter::AudioAssetRevision.token(record, version: library.latest(record)) }
  end

  def move_selection(rows, destination = folder.id.to_s)
    described_class.new(context: context).call(unit_id: unit.id.to_s, folder_id: destination, items: rows)
  end

  it 'moves only the selected metadata atomically and preserves identities and native unit' do
    request = items
    result = move_selection(request)
    expect(result.pluck('id')).to eq(assets.map { |record| record.id.to_s })
    expect(assets.map { |record| record.reload.folder_id }).to eq([folder.id, folder.id])
    expect(assets.map(&:unit_id)).to eq([unit.id, unit.id])
    expect(result.map { |row| row.fetch('revision') }).not_to eq(request.pluck('expected_revision'))
    expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
  end

  it 'requires review again after any source revision changes and never partially moves earlier selections' do
    request = items
    assets.last.update!(description: 'SYNTHETIC concurrent edit')
    expect { move_selection(request) }.to raise_error(JrcContactCenter::OperationError, 'stale_configuration_revision')
    expect(assets.map { |record| record.reload.folder_id }).to eq([nil, nil])
    expect(assets.last.description).to eq('SYNTHETIC concurrent edit')
  end

  it 'requires the existing revision precondition even when the target is the current root' do
    request = items
    request.last['expected_revision'] = nil
    expect { move_selection(request, nil) }.to raise_error(JrcContactCenter::OperationError, 'configuration_revision_required')
    expect(assets.map { |record| record.reload.folder_id }).to eq([nil, nil])
  end

  it 'denies an inaccessible destination without moving or exposing any audio' do
    request = items
    denied = JrcContactCenter::AudioFolder.create!(account: account, unit: units.last, name: 'SYNTHETIC private destination')
    expect { move_selection(request, denied.id.to_s) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(assets.map { |record| record.reload.folder_id }).to eq([nil, nil])
  end

  it 'does not mix individually authorized units in the same move operation' do
    request = items
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'GROUP', active: true, structure_managed: true)
    other = JrcContactCenter::AudioAsset.create!(account: account, unit: units.last, name: 'SYNTHETIC other authorized source')
    request << move_descriptor(other)
    expect { move_selection(request) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(assets.map { |record| record.reload.folder_id }).to eq([nil, nil])
    expect(other.reload.folder_id).to be_nil
  end

  it 'denies an asset from another account despite a known valid revision' do
    request = items
    foreign = create(:account)
    foreign_unit = JrcContactCenter::Unit.create!(account: foreign, code: 'MOVE-FOREIGN', name: 'SYNTHETIC foreign unit', kind: 'sac')
    hidden = JrcContactCenter::AudioAsset.create!(account: foreign, unit: foreign_unit, name: 'SYNTHETIC foreign source')
    request << { 'audio_asset_id' => hidden.id.to_s, 'expected_revision' => JrcContactCenter::AudioAssetRevision.token(hidden, version: nil) }
    expect { move_selection(request) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(assets.map { |record| record.reload.folder_id }).to eq([nil, nil])
    expect(hidden.reload.folder_id).to be_nil
  end

  it 'reauthorizes the current profile instead of treating a known revision as permission' do
    request = items
    service = described_class.new(context: context)
    member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_recordings_listen])
    expect { service.call(unit_id: unit.id.to_s, folder_id: folder.id.to_s, items: request) }.to raise_error(Pundit::NotAuthorizedError)
    expect(assets.map { |record| record.reload.folder_id }).to eq([nil, nil])
  end

  it 'does not duplicate audits when a fresh reviewed selection already belongs to the target folder' do
    move_selection(items)
    audits = Audited.audit_class.where(auditable: assets).count
    result = move_selection(assets.map { |record| move_descriptor(record.reload) })
    expect(result.length).to eq(2)
    expect(Audited.audit_class.where(auditable: assets).count).to eq(audits)
    expect(assets.map { |record| record.reload.folder_id }).to eq([folder.id, folder.id])
  end

  it 'preserves actual native bytes, immutable versions and inspection while moving back to root' do
    version = JrcContactCenter::AudioUploads.new(access: library).create!(
      unit_id: unit.id, attributes: { name: 'SYNTHETIC actual move source', folder_id: folder.id.to_s }, file: upload, key: key
    )
    original = version.reload.attributes
    proof = version.latest_inspection.attributes
    move_selection([move_descriptor(version.audio_asset)], nil)
    expect(version.audio_asset.reload.folder_id).to be_nil
    expect(version.reload.attributes).to eq(original)
    expect(version.latest_inspection.attributes).to eq(proof)
    expect(version.blob.download).to eq(bytes)
  end

  it 'rolls back all earlier moves and their audits if a later native audit fails' do
    request = items
    audit_count = Audited.audit_class.where(auditable: assets).count
    allow(JrcContactCenter::ConfigurationAudit).to receive(:write!).and_wrap_original do |original, record, **options|
      raise ActiveRecord::RecordInvalid, record if record.id == assets.last.id && options[:action] == 'update'

      original.call(record, **options)
    end
    expect { move_selection(request) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(assets.map { |record| record.reload.folder_id }).to eq([nil, nil])
    expect(Audited.audit_class.where(auditable: assets).count).to eq(audit_count)
  end
end

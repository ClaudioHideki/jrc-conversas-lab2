require 'rails_helper'
require Rails.root.join('script/jrc_call_center_audio_folder_seed')

RSpec.describe JrcContactCenter::SyntheticAudioFolderSeed do
  include_context 'with an institutional audio receipt'

  let(:queues) do
    units.map.with_index do |native_unit, index|
      JrcContactCenter::Queue.create!(account: account, unit: native_unit, code: "SYNTHETIC-Q#{index}",
                                      name: "SYNTHETIC queue #{index}", service_kind: 'sac', strategy: 'round_robin')
    end
  end

  it 'keeps metadata-only organization in its own native folder without changing existing destination or root pagination fixtures' do
    result = described_class.call(account: account, queues: queues, member: member)
    metadata = JrcContactCenter::AudioAsset.find(result.fetch(:metadata_audio_id))
    expect(metadata).to have_attributes(account_id: account.id, unit_id: unit.id, folder_id: result.fetch(:metadata_audio_folder_id).to_i)
    expect(metadata.versions).to be_empty
    expect(JrcContactCenter::AudioLibraryPresenter.asset(metadata).fetch('latest_version')).to be_nil
    expect(JrcContactCenter::AudioFolder.where(account: account, unit: unit).count).to eq(22)
    expect([result.fetch(:audio_folder_id), result.fetch(:audio_destination_id)]).not_to include(metadata.folder_id.to_s)
    expect(JrcContactCenter::AudioAsset.where(account: account, folder_id: result.fetch(:audio_destination_id))).to be_empty
    expect(JrcContactCenter::AudioAsset.where(account: account, unit: unit, folder_id: nil).count).to eq(2)
  end
end

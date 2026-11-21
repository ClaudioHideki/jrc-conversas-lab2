require 'rails_helper'
require Rails.root.join('script/jrc_call_center_ivr_audio_seed')

RSpec.describe JrcContactCenter::SyntheticIvrAudioSeed do
  include_context 'with an institutional audio receipt'

  let(:target) { { account_id: account.id, allowed_unit_id: unit.id, administrator: { 'uid' => actor.email } } }

  it 'creates an authorized genuinely unverified private version with no fabricated inspection' do
    account.update!(name: 'SYNTHETIC IVR owned fixture')
    described_class.call(targets: { owned: target })
    reference = target.fetch(:unverified_audio_ref)
    access = JrcContactCenter::AudioLibraryAccess.new(context: context)
    version = access.versions(access.asset(reference.fetch(:asset_id))).find(reference.fetch(:version_id))
    expect(version.account_id).to eq(account.id)
    expect(version.unit_id).to eq(unit.id)
    expect(version.created_by_id).to eq(actor.id)
    expect(version.sha256).to eq(reference.fetch(:sha256))
    expect(version.blob.download).to eq(bytes)
    expect(version.latest_inspection).to be_nil
    expect(JrcContactCenter::AudioInspection.where(audio_version: version)).to be_empty
  end

  it 'refuses a non-owned environment before looking up any account or touching storage' do
    expect(Account).not_to receive(:find)
    with_modified_env GITHUB_ACTIONS: nil do
      expect { described_class.call(targets: { owned: target }) }.to raise_error(RuntimeError)
    end
  end

  it 'refuses a non-synthetic account even in the disposable database' do
    account.update!(name: 'Not an owned IVR fixture')
    expect { described_class.call(targets: { owned: target }) }.to raise_error(RuntimeError, 'Owned synthetic IVR account required')
    expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
  end

  it 'does not expand unit coverage for a caller who can configure only the first unit' do
    account.update!(name: 'SYNTHETIC IVR owned fixture')
    target[:allowed_unit_id] = units.last.id
    expect { described_class.call(targets: { owned: target }) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
    expect(target).not_to have_key(:unverified_audio_ref)
  end
end

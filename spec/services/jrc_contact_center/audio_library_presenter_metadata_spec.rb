require 'rails_helper'

RSpec.describe JrcContactCenter::AudioLibraryPresenter do
  include_context 'with an institutional audio receipt'

  let(:access) { JrcContactCenter::AudioLibraryAccess.new(context: context) }
  let(:versions) do
    (1..3).map do |index|
      JrcContactCenter::AudioUploads.new(access: access).create!(
        unit_id: unit.id, attributes: { name: "SYNTHETIC batch #{index}" }, file: upload, key: "synthetic-batch-metadata-#{index}"
      )
    end
  end

  it 'loads the latest observation in one native batch instead of querying the inspection history separately for each file' do
    sources = versions
    queries = []
    subscriber = lambda do |*, payload|
      queries << payload[:sql] if payload[:sql].match?(/\bFROM\s+"jrc_contact_center_audio_(?:versions|inspections)"/i)
    end
    rows = ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      access.assets.where(unit_id: unit.id).order(:id).map { |asset| described_class.asset(asset) }
    end
    expect(rows.map { |row| row.fetch('latest_version').fetch('id') }).to eq(sources.map { |source| source.id.to_s })
    expect(rows.map { |row| row.fetch('latest_version').fetch('technical_verification').fetch('ready') }).to eq([true, true, true])
    expect(queries.count { |query| query.include?('FROM "jrc_contact_center_audio_inspections"') }).to eq(1)
    expect(queries.count { |query| query.include?('FROM "jrc_contact_center_audio_versions"') }).to eq(1)
    expect(rows.map { |row| row.fetch('latest_version').fetch('technical_verification').fetch('metadata').fetch('duration_ms') }).to eq([1, 1, 1])
  end
end

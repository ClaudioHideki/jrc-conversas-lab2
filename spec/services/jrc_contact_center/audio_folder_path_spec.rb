require 'rails_helper'

RSpec.describe JrcContactCenter::AudioFolderPath do
  let(:account) { create(:account) }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, code: 'PATH-A', name: 'SYNTHETIC path unit', kind: 'sac') }
  let(:root) { JrcContactCenter::AudioFolder.create!(account: account, unit: unit, name: 'SYNTHETIC root') }
  let(:child) { JrcContactCenter::AudioFolder.create!(account: account, unit: unit, parent: root, name: 'SYNTHETIC child') }
  let(:scope) { JrcContactCenter::AudioFolder.where(account: account, unit: unit) }

  before do
    config = ActiveRecord::Base.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && config.database == 'jrc_sd_bc_portal_concurrency_20261025_test'
    raise 'Audio folder path tests require the exclusively owned disposable database' unless owned
  end

  it 'returns stable native identities and names from root through the current folder' do
    result = described_class.new(folder: child, scope: scope).call
    expect(result).to eq([{ 'id' => root.id.to_s, 'name' => root.name }, { 'id' => child.id.to_s, 'name' => child.name }])
  end

  it 'queries a deep authorized hierarchy once rather than loading an ancestor per request' do
    leaf = root
    12.times do |index|
      leaf = JrcContactCenter::AudioFolder.create!(account: account, unit: unit, parent: leaf, name: "SYNTHETIC level #{index}")
    end
    queries = []
    subscriber = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] if payload[:sql].start_with?('WITH RECURSIVE') }
    result = ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      described_class.new(folder: leaf, scope: scope).call
    end
    expect(result.length).to eq(13)
    expect(result.first.fetch('id')).to eq(root.id.to_s)
    expect(result.last.fetch('id')).to eq(leaf.id.to_s)
    expect(queries.length).to eq(1)
  end

  it 'fails closed if the caller relation cannot see an ancestor instead of exposing its name' do
    selected = scope.where(id: child.id)
    expect { described_class.new(folder: child, scope: selected).call }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'does not return a path through another native operational unit' do
    foreign_unit = JrcContactCenter::Unit.create!(account: account, code: 'PATH-B', name: 'SYNTHETIC denied unit', kind: 'sac')
    foreign = JrcContactCenter::AudioFolder.create!(account: account, unit: foreign_unit, name: 'SYNTHETIC hidden unit')
    expect { described_class.new(folder: foreign, scope: scope).call }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'does not return a path from a foreign account even if its folder object is supplied' do
    foreign_account = create(:account)
    foreign_unit = JrcContactCenter::Unit.create!(account: foreign_account, code: 'PATH-F', name: 'SYNTHETIC foreign unit', kind: 'sac')
    foreign = JrcContactCenter::AudioFolder.create!(account: foreign_account, unit: foreign_unit, name: 'SYNTHETIC hidden account')
    expect { described_class.new(folder: foreign, scope: scope).call }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'terminates and reports a corrupt synthetic database cycle without returning a partial breadcrumb' do
    descendant = child
    JrcContactCenter::AudioFolder.connection.execute(<<~SQL.squish)
      UPDATE jrc_contact_center_audio_folders SET parent_id = #{descendant.id}
      WHERE id = #{root.id} AND account_id = #{account.id}
    SQL
    expect { described_class.new(folder: descendant, scope: scope).call }.to raise_error(JrcContactCenter::OperationError) do |error|
      expect(error.code).to eq('invalid_audio_folder_hierarchy')
    end
  end
end

require 'rails_helper'

RSpec.describe JrcContactCenter::AudioFolder do
  let(:account) { create(:account) }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, code: 'SYNTHETIC', name: 'SYNTHETIC unit', kind: 'sac') }
  let(:root) { described_class.create!(account: account, unit: unit, name: 'SYNTHETIC root') }

  before do
    config = ActiveRecord::Base.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' &&
            %w[jrc_sd_bc_portal_concurrency_20261025_test jrc_cc_access_schema_reload_synthetic].include?(config.database)
    raise 'Audio folder tests require an exclusively owned disposable database' unless owned
  end

  it 'rejects another account unit in both the model and the real database origin constraint' do
    foreign = create(:account)
    expect(described_class.new(account: foreign, unit: unit, name: 'SYNTHETIC denied')).not_to be_valid
    expect do
      described_class.transaction(requires_new: true) do
        described_class.connection.execute(<<~SQL.squish)
          INSERT INTO jrc_contact_center_audio_folders (account_id, unit_id, name, created_at, updated_at)
          VALUES (#{foreign.id}, #{unit.id}, 'SYNTHETIC denied', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        SQL
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(described_class.where(account: foreign)).to be_empty
  end

  it 'rejects cross-unit parentage at the composite foreign key even when model validations are bypassed' do
    first = root
    other = JrcContactCenter::Unit.create!(account: account, code: 'OTHER', name: 'SYNTHETIC other unit', kind: 'sac')
    expect do
      described_class.transaction(requires_new: true) do
        described_class.connection.execute(<<~SQL.squish)
          INSERT INTO jrc_contact_center_audio_folders (account_id, unit_id, parent_id, name, created_at, updated_at)
          VALUES (#{account.id}, #{other.id}, #{first.id}, 'SYNTHETIC denied', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        SQL
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(first.reload.unit_id).to eq(unit.id)
  end

  it 'protects case-insensitive sibling uniqueness while permitting the same name under another parent' do
    first = root
    expect do
      described_class.transaction(requires_new: true) do
        described_class.connection.execute(<<~SQL.squish)
          INSERT INTO jrc_contact_center_audio_folders (account_id, unit_id, name, created_at, updated_at)
          VALUES (#{account.id}, #{unit.id}, 'synthetic ROOT', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        SQL
      end
    end.to raise_error(ActiveRecord::RecordNotUnique)
    nested = described_class.create!(account: account, unit: unit, parent: first, name: first.name)
    expect(nested.parent_id).to eq(first.id)
  end

  it 'prevents self-parentage in the model and database without fabricating a new audio identity' do
    first = root
    expect do
      described_class.transaction(requires_new: true) do
        described_class.connection.execute("UPDATE jrc_contact_center_audio_folders SET parent_id = id WHERE id = #{first.id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /cc_audio_folder_not_self/)
    first.parent = first
    expect(first).not_to be_valid
  end

  it 'blocks direct unit removal while owned folders exist' do
    root
    expect do
      described_class.transaction(requires_new: true) { JrcContactCenter::Unit.where(id: unit.id).delete_all }
    end.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(root.reload.unit_id).to eq(unit.id)
  end

  it 'retains native optimistic locking for stale folder instances' do
    first = root
    stale = described_class.find(first.id)
    first.update!(name: 'SYNTHETIC updated')
    expect { stale.update!(name: 'SYNTHETIC stale') }.to raise_error(ActiveRecord::StaleObjectError)
    expect(first.reload.name).to eq('SYNTHETIC updated')
  end

  it 'preserves native account deletion protection and an explicit owned dependency order' do
    first = root
    child = described_class.create!(account: account, unit: unit, parent: first, name: 'SYNTHETIC child')
    other = create(:account)
    foreign_unit = JrcContactCenter::Unit.create!(account: other, code: 'OTHER', name: 'SYNTHETIC foreign', kind: 'sac')
    foreign = described_class.create!(account: other, unit: foreign_unit, name: 'SYNTHETIC preserved')
    expect do
      described_class.transaction(requires_new: true) { Account.where(id: account.id).delete_all }
    end.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(described_class.where(id: [first.id, child.id]).count).to eq(2)
    described_class.where(account: account).delete_all
    JrcContactCenter::Unit.where(account: account).delete_all
    Account.where(id: account.id).delete_all
    expect(Account.exists?(account.id)).to be(false)
    expect(foreign.reload.account_id).to eq(other.id)
  end
end

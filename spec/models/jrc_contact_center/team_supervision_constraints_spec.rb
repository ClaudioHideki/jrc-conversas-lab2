require 'rails_helper'

RSpec.describe JrcContactCenter::TeamSupervision, 'native database boundaries' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:member) { account.account_users.find_by!(user: user) }
  let(:team) { create(:team, account: account) }
  let(:row) do
    { account_id: account.id, team_id: team.id, account_user_id: member.id, kind: 'additional',
      created_at: Time.current, updated_at: Time.current }
  end

  before do
    config = ActiveRecord::Base.connection_db_config
    owned = Rails.env.test? && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' && config.configuration_hash[:host] == '127.0.0.1' &&
            %w[jrc_sd_bc_portal_concurrency_20261025_test jrc_cc_access_schema_reload_synthetic].include?(config.database)
    raise 'Owned synthetic database required for raw constraint proofs' unless owned
  end

  # Explicit SQL proves database enforcement independently of the model validations above.
  def insert_raw(attributes)
    connection = ActiveRecord::Base.connection
    keys = attributes.keys
    columns = keys.map { |key| connection.quote_column_name(key) }.join(', ')
    values = keys.map { |key| connection.quote(attributes.fetch(key)) }.join(', ')
    connection.execute("INSERT INTO #{described_class.quoted_table_name} (#{columns}) VALUES (#{values})")
  end

  it 'rejects a foreign native team through its composite account FK even when model validation is bypassed' do
    foreign_team = create(:team, account: create(:account))
    expect do
      JrcContactCenter::TeamSupervision.transaction(requires_new: true) do
        insert_raw(row.merge(team_id: foreign_team.id))
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it 'rejects a foreign native member through its composite account FK even when model validation is bypassed' do
    foreign = create(:user, account: create(:account))
    foreign_member = foreign.account_users.sole
    expect do
      JrcContactCenter::TeamSupervision.transaction(requires_new: true) do
        insert_raw(row.merge(account_user_id: foreign_member.id))
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it 'enforces one principal per team in PostgreSQL rather than relying only on a validation race' do
    insert_raw(row.merge(kind: 'primary'))
    second = create(:user, account: account)
    second_member = account.account_users.find_by!(user: second)
    expect do
      JrcContactCenter::TeamSupervision.transaction(requires_new: true) do
        insert_raw(row.merge(account_user_id: second_member.id, kind: 'primary'))
      end
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'does not allow the same native person to occupy both operational roles in one team' do
    insert_raw(row)
    expect do
      JrcContactCenter::TeamSupervision.transaction(requires_new: true) do
        insert_raw(row.merge(kind: 'primary'))
      end
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'enforces the exact kind check rather than accepting an invented grant or operator role' do
    expect do
      JrcContactCenter::TeamSupervision.transaction(requires_new: true) do
        insert_raw(row.merge(kind: 'agent'))
      end
    end.to raise_error(ActiveRecord::StatementInvalid) { |error|
      expect(error.cause.result.error_field(PG::Result::PG_DIAG_CONSTRAINT_NAME)).to eq('cc_team_supervision_kind')
    }
  end
end

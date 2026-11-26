# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261126193000_create_contact_center_quality_reviews')

RSpec.describe CreateContactCenterQualityReviews do
  let(:migration) { described_class.new }
  let(:connection) { ApplicationRecord.connection }
  let(:table) { described_class::TABLE }

  it 'verifies a repeated installation without changing populated settings, members or granting a review capability' do
    account = create(:account)
    settings = account.settings.deep_dup
    members = account.account_users.order(:id).map(&:attributes)
    expect { migration.up }.not_to raise_error
    expect(account.reload.settings).to eq(settings)
    expect(account.account_users.order(:id).map(&:attributes)).to eq(members)
    expect(JrcContactCenter::QualityReviewRevision.where(account: account)).to be_empty
  end

  it 'refuses missing append and immutable guards instead of silently repairing unknown history' do
    %w[cc_quality_review_append_guard cc_quality_review_immutable_guard].each do |trigger|
      expect do
        ApplicationRecord.transaction(requires_new: true) do
          connection.execute("DROP TRIGGER #{trigger} ON #{table}")
          migration.up
        end
      end.to raise_error(ActiveRecord::MigrationError, /Unknown quality review references or guards/)
    end
  end

  it 'detects a disabled immutable trigger even when its name and function have not changed' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        connection.execute("ALTER TABLE #{table} DISABLE TRIGGER cc_quality_review_immutable_guard")
        migration.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unknown quality review schema/)
  end

  it 'detects an altered account reference, CHECK, index or schema receipt without erasing history' do
    mutations = [
      -> { connection.remove_foreign_key(table, name: 'cc_quality_review_account_fk') },
      -> { connection.remove_check_constraint(table, name: 'cc_quality_review_reason') },
      -> { connection.remove_index(table, name: 'cc_quality_review_request') },
      -> { connection.change_table_comment(table, 'SYNTHETIC changed quality schema') }
    ]
    mutations.each do |mutate|
      expect do
        ApplicationRecord.transaction(requires_new: true) do
          mutate.call
          migration.up
        end
      end.to raise_error(ActiveRecord::MigrationError, /Unknown quality review/)
    end
  end

  it 'keeps a normal down migration from deleting human corrections' do
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    expect(connection.table_exists?(table)).to be(true)
  end
end

require 'rails_helper'
require Rails.root.join('db/migrate/20261121003000_add_contact_center_quality_review_authority')

RSpec.describe AddContactCenterQualityReviewAuthority, type: :model do
  let(:connection) { ActiveRecord::Base.connection }
  let(:migration) { described_class.new }
  let(:table) { described_class::TABLE }
  let(:account) { create(:account) }
  let(:user) { create(:user, :contact_center_eligible, account: account) }
  let(:member) { account.account_users.find_by!(user: user) }
  let(:grant) { JrcContactCenter::AccessGrant.find_by!(account_user: member) }
  let(:review) { described_class::REVIEW_CAPABILITY }

  before do
    databases = %w[jrc_sd_bc_portal_concurrency_20261025_test jrc_cc_access_schema_reload_synthetic]
    owned = Rails.env.test? && ENV['POSTGRES_HOST'] == '127.0.0.1' && databases.include?(connection.current_database)
    raise 'Owned synthetic migration database required' unless owned
  end

  def expression(field, capabilities)
    entries = capabilities.map { |capability| "#{connection.quote(capability)}::text" }.join(', ')
    "#{field} <@ ARRAY[#{entries}]"
  end

  def replace_constraint(field, capabilities, validate: true)
    name = "cc_access_#{field}_known"
    connection.remove_check_constraint(table, name: name)
    connection.add_check_constraint(table, expression(field, capabilities), name: name, validate: validate)
  end

  def legacy_constraints
    described_class::FIELDS.each { |field| replace_constraint(field, described_class::LEGACY_CAPABILITIES) }
  end

  def definitions
    connection.check_constraints(table).to_h { |constraint| [constraint.name, [constraint.expression, constraint.validate?]] }
  end

  it 'accepts an already upgraded installation without manufacturing grants' do
    previous = definitions
    rows = JrcContactCenter::AccessGrant.order(:id).map(&:attributes)
    migration.up
    expect(definitions).to eq(previous)
    expect(JrcContactCenter::AccessGrant.order(:id).map(&:attributes)).to eq(rows)
    expect(definitions.fetch('cc_access_allowed_known').first).to include(review)
    expect(definitions.fetch('cc_access_denied_known').first).to include(review)
  end

  it 'upgrades populated legacy grants atomically without changing eligibility, denials, teams or audit' do
    grant.update!(eligible: false, allowed: ['jrc_contact_center_publish'], denied: ['jrc_contact_center_recordings_download'])
    team = create(:team, account: account)
    JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: ['jrc_contact_center_operate'])
    legacy_constraints
    previous = JrcContactCenter::AccessGrant.order(:id).map(&:attributes)
    audits = Audited.audit_class.count
    migration.up
    migration.up
    expect(JrcContactCenter::AccessGrant.order(:id).map(&:attributes)).to eq(previous)
    expect(Audited.audit_class.count).to eq(audits)
    expect(connection.foreign_keys(table).length).to eq(3)
    expect(definitions.length).to eq(4)
    expect(grant.reload.allowed).not_to include(review)
  end

  %w[allowed denied].each do |field|
    it "admits explicit #{field} review values only after the forward migration" do
      grant
      legacy_constraints
      expect do
        connection.transaction(requires_new: true) { grant.update_column(field, [review]) }
      end.to raise_error(ActiveRecord::StatementInvalid)
      migration.up
      grant.reload.update_column(field, [review])
      expect(grant.reload.public_send(field)).to eq([review])
    end

    it "continues rejecting unknown #{field} rights at the SQL boundary" do
      grant
      expect do
        connection.transaction(requires_new: true) { grant.update_column(field, ['unregistered_review_admin']) }
      end.to raise_error(ActiveRecord::StatementInvalid)
      expect(grant.reload.public_send(field)).to eq([])
    end

    it "refuses an unvalidated #{field} constraint instead of treating it as a proved schema" do
      replace_constraint(field, described_class::LEGACY_CAPABILITIES, validate: false)
      previous = definitions
      expect { migration.up }.to raise_error(ActiveRecord::MigrationError, /Unexpected access constraints/)
      expect(definitions).to eq(previous)
    end
  end

  it 'refuses an unknown capability expansion even when the four original names still exist' do
    replace_constraint('allowed', described_class::LEGACY_CAPABILITIES + ['unregistered_review_admin'])
    previous = definitions
    expect { migration.up }.to raise_error(ActiveRecord::MigrationError, /Unexpected access constraints/)
    expect(definitions).to eq(previous)
  end

  it 'refuses a weakened subject constraint without modifying either capabilities constraint' do
    connection.remove_check_constraint(table, name: 'cc_access_one_subject')
    connection.add_check_constraint(table, 'account_id IS NOT NULL', name: 'cc_access_one_subject')
    previous = definitions
    expect { migration.up }.to raise_error(ActiveRecord::MigrationError, /Unexpected access constraints/)
    expect(definitions).to eq(previous)
  end

  it 'rolls back the first replacement if the second fails without dropping any persisted grants' do
    grant
    legacy_constraints
    previous = definitions
    attributes = grant.attributes
    allow(migration).to receive(:add_check_constraint).and_wrap_original do |original, *args, **options|
      raise ActiveRecord::MigrationError, 'SYNTHETIC second-constraint failure' if options[:name] == 'cc_access_denied_known'

      original.call(*args, **options)
    end
    expect { migration.up }.to raise_error(ActiveRecord::MigrationError, /SYNTHETIC second-constraint failure/)
    expect(definitions).to eq(previous)
    expect(grant.reload.attributes).to eq(attributes)
  end

  it 'refuses rollback instead of silently stripping a persisted grant or explicit denial' do
    grant.update!(allowed: [review], denied: [review])
    previous = grant.attributes
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    expect(grant.reload.attributes).to eq(previous)
    expect(definitions.fetch('cc_access_allowed_known').first).to include(review)
  end
end

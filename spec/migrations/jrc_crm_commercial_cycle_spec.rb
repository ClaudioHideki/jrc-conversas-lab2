require 'rails_helper'

RSpec.describe 'Commercial migrations on the official R2 schema', type: :model do
  it 'round-trips the eight commercial migrations without altering existing module tables' do
    versions = %w[20260918110000 20260918120000 20260918130000 20260919233000
                  20260920010000 20260920011000 20260920012000 20260920173000]
    connection = ActiveRecord::Base.connection
    migrations = connection.migration_context.migrations.select { |migration| versions.include?(migration.version.to_s) }
    expect(migrations.length).to eq(8)
    query = <<~SQL
      SELECT table_name, column_name, data_type, is_nullable, column_default
      FROM information_schema.columns WHERE table_schema = 'public'
      ORDER BY table_name, column_name
    SQL
    before = connection.select_all(query).to_a
    protected = before.reject { |row| row['table_name'].start_with?('jrc_crm_') }
    connection.transaction(requires_new: true) do
      migrations.reverse_each { |migration| migration.migrate(:down) }
      expect(connection.table_exists?(:jrc_crm_sales_orders)).to be(false)
      expect(connection.column_exists?(:jrc_crm_proposals, :shipping_cents)).to be(false)
      expect(connection.column_exists?(:jrc_crm_proposals, :shipping_in_installments)).to be(false)
      expect(connection.column_exists?(:jrc_crm_deals, :business_unit_id)).to be(false)
      expect(connection.select_all(query).to_a.reject { |row| row['table_name'].start_with?('jrc_crm_') }).to eq(protected)
      migrations.each { |migration| migration.migrate(:up) }
      expect(connection.select_all(query).to_a).to eq(before)
      raise ActiveRecord::Rollback
    end
  ensure
    connection.schema_cache.clear! if connection
  end
end

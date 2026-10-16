class JrcFlows::OwnershipLedger < ActiveRecord::Base
  self.abstract_class = true
  # This is a separate pool, not requires_new on the runner's connection.
  establish_connection(ApplicationRecord.connection_db_config.configuration_hash.merge(pool: 5))

  def self.transaction_sql
    connection_pool.with_connection do |connection|
      connection.transaction(requires_new: true) { yield connection }
    end
  end

  def self.sql(template, *values)
    sanitize_sql_array([template, *values])
  end
end

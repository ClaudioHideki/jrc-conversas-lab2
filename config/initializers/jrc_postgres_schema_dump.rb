require 'active_record/schema_dumper'
require 'digest'
require Rails.root.join('lib/jrc_postgres_schema_dumper')

# Reuse HairTrigger's trailer hook; override its PostgreSQL name-only trigger map.
# PostgreSQL allows equal trigger names on different tables, including the E2 ledger.
ActiveRecord::SchemaDumper.prepend(JrcPostgresSchemaDumper)

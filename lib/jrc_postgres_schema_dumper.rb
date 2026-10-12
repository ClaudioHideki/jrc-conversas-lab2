# HairTrigger indexes PostgreSQL triggers by name, losing equal names on different tables.
# Dump the actual definitions through its existing hook, preserving every ledger guard.
module JrcPostgresSchemaDumper
  private

  def triggers(stream)
    if @connection.adapter_name == 'PostgreSQL'
      # Rails 7.1's Ruby reconstruction normalizes array casts and loses NOT VALID on checks.
      # Restore the exact database definitions after the native table/index DSL has loaded.
      checks = @connection.select_all(<<~SQL).flat_map do |row|
        SELECT c.relname, k.conname, pg_get_constraintdef(k.oid) AS definition
        FROM pg_constraint k JOIN pg_class c ON c.oid = k.conrelid JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND k.contype = 'c' ORDER BY c.relname, k.conname
      SQL
        table, name = @connection.quote_table_name(row['relname']), @connection.quote_column_name(row['conname'])
        ["ALTER TABLE #{table} DROP CONSTRAINT #{name};", "ALTER TABLE #{table} ADD CONSTRAINT #{name} #{row['definition']};"]
      end
      indexes = @connection.select_all(<<~SQL).flat_map do |row|
        SELECT c.relname, pg_get_indexdef(i.indexrelid) AS definition FROM pg_index i
        JOIN pg_class c ON c.oid = i.indexrelid JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND i.indpred IS NOT NULL ORDER BY c.relname
      SQL
        ["DROP INDEX #{@connection.quote_table_name(row['relname'])};", "#{row['definition']};"]
      end
      functions = @connection.select_values(<<~SQL)
        SELECT pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.prokind = 'f'
          AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass
            AND d.objid = p.oid AND d.deptype = 'e')
        ORDER BY p.proname, pg_get_function_identity_arguments(p.oid)
      SQL
      triggers = @connection.select_values(<<~SQL)
        SELECT pg_get_triggerdef(t.oid, true) || ';' FROM pg_trigger t
        JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND NOT t.tgisinternal
        ORDER BY c.relname, t.tgname
      SQL
      (checks + indexes + functions + triggers).each do |statement|
        separator = "JRC_SCHEMA_SQL_#{Digest::SHA256.hexdigest(statement)[0, 12]}"
        stream.puts "  execute <<~'#{separator}'"
        statement.each_line { |line| stream.puts "    #{line.rstrip}" }
        stream.puts "  #{separator}"
        stream.puts
      end
    end
    super unless @connection.adapter_name == 'PostgreSQL'
  end
end

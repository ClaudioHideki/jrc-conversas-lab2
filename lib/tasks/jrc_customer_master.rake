namespace :jrc do
  namespace :customer_master do
    desc 'Dry-run default. ACCOUNT_ID required. APPLY=1 requires REVIEWED_SHA256; MAPPINGS is an optional reviewed JSON file.'
    task backfill: :environment do
      require 'json'
      account = Account.find(Integer(ENV.fetch('ACCOUNT_ID')))
      mappings = ENV['MAPPINGS'].present? ? JSON.parse(File.read(ENV.fetch('MAPPINGS'))) : {}
      raise ArgumentError, 'MAPPINGS must be an object of organization_id => company_id' unless mappings.is_a?(Hash)

      service = JrcCustomers::Backfill.new(account: account, mappings: mappings)
      report = ENV['APPLY'] == '1' ? service.apply_reviewed!(reviewed_digest: ENV.fetch('REVIEWED_SHA256')) : service.run
      puts JSON.pretty_generate(report)
      abort 'Conflicts require manual review; feature was not enabled.' if report[:conflicts].any?
    end

    desc 'Operational dry-run; APPLY=1 requires REVIEWED_SHA256 from the reviewed output. Run after CRM backfill.'
    task backfill_operations: :environment do
      require 'json'
      account = Account.find(Integer(ENV.fetch('ACCOUNT_ID')))
      service = JrcCustomers::OperationsBackfill.new(account: account)
      report = ENV['APPLY'] == '1' ? service.apply!(reviewed_digest: ENV.fetch('REVIEWED_SHA256')) : service.plan
      puts JSON.pretty_generate(report)
      abort 'Resolve operational conflicts; feature remains unchanged.' if report[:conflicts].any?
    end

    desc 'Enable ONE account only after native QA and clean backfill. CONFIRM=ENABLE and HOMOLOGATION=APPROVED required.'
    task enable: :environment do
      abort 'Native QA must be approved before enabling.' unless ENV['CONFIRM'] == 'ENABLE' && ENV['HOMOLOGATION'] == 'APPROVED'
      account = Account.find(Integer(ENV.fetch('ACCOUNT_ID')))
      account.with_lock do
        report = JrcCustomers::Backfill.new(account: account).run
        puts JSON.pretty_generate(report)
        pending_links = Array(report[:contacts_linked]).any? || Array(report[:leads_linked]).any? || Array(report[:crm_links]).any?
        abort 'Apply and review backfill before enabling.' if report[:conflicts].any? || report[:remaining_unmapped_organizations].to_i.positive? || pending_links
        operations = JrcCustomers::OperationsBackfill.new(account: account).plan
        puts JSON.pretty_generate(operations)
        abort 'Review/apply operational backfill before enabling.' if operations[:conflicts].any? || operations[:pending].any?
        unvalidated = ActiveRecord::Base.connection.select_values("SELECT conname FROM pg_constraint WHERE NOT convalidated AND conname LIKE 'jrc_master_%'")
        abort 'Validate the new master constraints before enabling.' if unvalidated.any?
        account.enable_features('jrc_customer_master')
        account.save!
      end
      puts "Enabled for account #{account.id}; no other account changed."
    end

    desc 'Disable the new UI/consumers for ONE account; retain all data and new schema.'
    task disable: :environment do
      abort 'CONFIRM=DISABLE required.' unless ENV['CONFIRM'] == 'DISABLE'
      account = Account.find(Integer(ENV.fetch('ACCOUNT_ID')))
      account.disable_features('jrc_customer_master')
      account.save!
      puts "Disabled for account #{account.id}; no tables or rows removed."
    end

    desc 'Validate new database tenant constraints after reviewing all accounts. CONFIRM=VALIDATE required.'
    task validate: :environment do
      abort 'Set CONFIRM=VALIDATE after reviewing backfill reports and taking a backup.' unless ENV['CONFIRM'] == 'VALIDATE'
      connection = ActiveRecord::Base.connection
      tables = %w[contacts companies jrc_crm_organizations jrc_crm_leads jrc_crm_deals jrc_crm_activities company_addresses contact_points jrc_service_desk_tickets jrc_projects_projects jrc_crm_sales_orders jrc_crm_contracts jrc_crm_invoices jrc_crm_backoffice_requests]
      tables.each do |table|
        connection.check_constraints(table).select { |key| key.name.start_with?('jrc_master_') }.each do |key|
          connection.validate_check_constraint(table, name: key.name)
          puts "validated #{table}.#{key.name}"
        end
        connection.foreign_keys(table).select { |key| key.name.start_with?('jrc_master_') }.each do |key|
          connection.validate_foreign_key(table, name: key.name)
          puts "validated #{table}.#{key.name}"
        end
      end
    end
  end
end

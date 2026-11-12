# Run only through `bundle exec rails runner`, in the integration's isolated test
# environment. READ ONLY. No configuration, user or grant is modified.
# Verify ownership/isolation outside this script; matching a name alone is not proof.
require 'json'

abort 'BLOCKED: Rails test environment required' unless defined?(Rails) && Rails.env.test?
connection = ActiveRecord::Base.connection
settings = ActiveRecord::Base.connection_db_config.configuration_hash
expected_db = ENV['JRC_ROLE_AUDIT_DATABASE'].to_s
expected_host = ENV['JRC_ROLE_AUDIT_HOST'].to_s
abort 'BLOCKED: explicit database and host confirmation required' if expected_db.empty? || expected_host.empty?
abort 'BLOCKED: database or host differs from confirmation' unless settings[:database].to_s == expected_db && settings[:host].to_s == expected_host
abort 'BLOCKED: run outside another transaction' if connection.open_transactions.positive?

result = { checked: 0, invalid: 0, incompatible_configuration_ids: [], details: [], changed: false, native_acceptance: false }
JrcRelationship::Configuration.transaction do
  connection.execute('SET TRANSACTION READ ONLY')
  JrcRelationship::Configuration.where("jsonb_exists(rules, ?)", JrcRelationship::LocalAccess::KEY).find_each do |configuration|
    value = configuration.rules[JrcRelationship::LocalAccess::KEY]
    next if value.nil?

    result[:checked] += 1
    begin
      JrcRelationship::LocalRoleRules.normalize!(value)
    rescue ArgumentError => error
      result[:invalid] += 1
      # Only identifiers and validator messages, never names, grants or raw rules.
      if result[:details].size < 100
        result[:incompatible_configuration_ids] << configuration.id
        result[:details] << { configuration_id: configuration.id, reason: error.message }
      end
    end
  end
end
result[:status] = result[:invalid].zero? ? 'NO_INCOMPATIBLE_LOCAL_ROLES_FOUND_NOT_HOMOLOGATED' : 'BLOCKED_REQUIRES_REVIEWED_CONFIGURATION_CHANGE'
puts JSON.pretty_generate(result)
exit(result[:invalid].zero? ? 0 : 2)

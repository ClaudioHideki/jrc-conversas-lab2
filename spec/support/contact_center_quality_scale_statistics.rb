# frozen_string_literal: true

require 'digest'

# QA only, never loaded by Rails application initialization. No DML, grants,
# timeout changes or planner switches; inspect the same native fixture data.
module ContactCenterQualityScaleStatistics
  TABLES = %w[telephony_call_records jrc_contact_center_call_sessions jrc_contact_center_call_legs].freeze

  def owned_quality_scale_database!
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'jrc_sd_bc_portal_concurrency_20261025_test'
    raise 'Owned GitHub disposable quality scale database required' unless owned
  end

  def scale_fixture_identity
    sources = [
      [TelephonyCallRecord, %i[id account_id external_unique_id extension external_tenant has_recording]],
      [JrcContactCenter::CallSession, %i[id account_id external_session_id contact_id company_id current_unit_id current_queue_id]],
      [JrcContactCenter::CallLeg, %i[id account_id call_session_id account_user_id queue_id]]
    ]
    sources.to_h do |model, columns|
      rows = model.where(account: account).order(:id).pluck(*columns)
      [model.table_name, { count: rows.length, identity_sha256: Digest::SHA256.hexdigest(rows.to_json) }]
    end
  end

  def prepare_owned_scale_statistics
    owned_quality_scale_database!
    @scale_fixture_statistics = {
      sha: ENV.fetch('GITHUB_SHA'), synthetic: true, tables: TABLES,
      identity_before: scale_fixture_identity, plan_before: scale_query_plan,
      statement_timeout_before: ApplicationRecord.connection.select_value('SHOW statement_timeout')
    }
    ApplicationRecord.connection.execute('ANALYZE telephony_call_records, jrc_contact_center_call_sessions, jrc_contact_center_call_legs')
    @scale_fixture_statistics.merge!(identity_after: scale_fixture_identity, plan_after: scale_query_plan,
                                     statement_timeout_after: ApplicationRecord.connection.select_value('SHOW statement_timeout'))
  end

  def record_owned_scale_statistics
    owned_quality_scale_database!
    data = response.parsed_body
    receipt = @scale_fixture_statistics.merge(
      status: response.status, actual_total: data.dig('meta', 'total'), actual_universe: data.dig('quality_summary', 'universe'),
      actual_page_size: data.fetch('items', []).length, data_or_permission_mutation: false,
      statement_timeout_changed: false, planner_switches_changed: false, raw_SQL_bindings_or_rows_exported: false
    )
    File.write('/tmp/call-center-quality-scale-statistics.json', JSON.generate(receipt))
  end
end

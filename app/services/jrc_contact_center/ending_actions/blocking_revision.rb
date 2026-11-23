# frozen_string_literal: true

# Evidence only, never authorization. The executor must call this inside the
# native account authority transaction before a pending effect/retry, after
# revalidating the original actor and source/destination. Completed receipts are
# read independently; deactivation never rewrites them or the pinned definition.
class JrcContactCenter::EndingActions::BlockingRevision
  QUERY = <<~SQL.squish.freeze
    SELECT revision FROM jrc_contact_center_ending_action_versions
    WHERE account_id = $1 AND revision > $2 AND NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(private_definition -> 'entries') AS entry
      WHERE entry ->> 'code' = $3 AND entry -> 'active' = 'true'::jsonb
    ) ORDER BY revision LIMIT 1
  SQL

  def initialize(account:, version_id:, rule_code:)
    @account = account
    @version_id = version_id
    @rule_code = rule_code
  end

  def call
    JrcContactCenter::EndingActions::Catalogue.new(account: @account).verify_synchronized!
    version = JrcContactCenter::EndingActionVersion.where(account: @account).find(@version_id)
    validate_origin!(version)
    result = JrcContactCenter::EndingActionVersion.connection.exec_query(QUERY, 'EndingActionPendingHistory', binds(version), prepare: true)
    result.first&.fetch('revision')
  end

  private

  def validate_origin!(version)
    definition = JrcContactCenter::EndingActions::RuleDefinition.new.call(version.definition)
    rule = definition.fetch('entries').find { |entry| entry.fetch('code') == @rule_code }
    raise JrcContactCenter::OperationError, 'ending_action_origin_unavailable' unless rule&.fetch('active')
  end

  def binds(version)
    model = JrcContactCenter::EndingActionVersion
    values = [['account_id', @account.id, model.type_for_attribute('account_id')],
              ['revision', version.revision, model.type_for_attribute('revision')],
              ['private_rule_code', @rule_code, ActiveRecord::Type::String.new]]
    values.map { |name, value, type| ActiveRecord::Relation::QueryAttribute.new(name, value, type) }
  end
end

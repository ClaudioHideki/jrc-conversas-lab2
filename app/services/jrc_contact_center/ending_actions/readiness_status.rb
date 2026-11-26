# frozen_string_literal: true

# Read-only metadata under the same current configuration/source/destination
# authority. A review is never an execution grant. Match immutable intermediate
# rule versions exactly, as the native prospective execution predicate does.
class JrcContactCenter::EndingActions::ReadinessStatus
  MATCHING_VERSIONS = <<~SQL.squish.freeze
    EXISTS (
      SELECT 1 FROM jrc_contact_center_ending_action_versions activation
      CROSS JOIN LATERAL jsonb_array_elements(activation.private_definition -> 'entries') activated
      WHERE activation.id = jrc_contact_center_ending_action_readinesses.version_id
        AND activation.account_id = jrc_contact_center_ending_action_readinesses.account_id
        AND activated ->> 'code' = jrc_contact_center_ending_action_readinesses.rule_code
        AND activated -> 'active' = 'true'::jsonb AND activation.revision <= ?
        AND NOT EXISTS (
          SELECT 1 FROM jrc_contact_center_ending_action_versions intermediate
          WHERE intermediate.account_id = activation.account_id AND intermediate.revision BETWEEN activation.revision AND ?
            AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(intermediate.private_definition -> 'entries') entry
              WHERE entry ->> 'code' = jrc_contact_center_ending_action_readinesses.rule_code AND entry = activated)
        )
    )
  SQL
  CURRENT_DEFINITION = <<~SQL.squish.freeze
    rule_sha256 = (
      SELECT encode(sha256(convert_to(entry::text, 'UTF8')), 'hex')
      FROM jrc_contact_center_ending_action_versions current_definition
      CROSS JOIN LATERAL jsonb_array_elements(current_definition.private_definition -> 'entries') entry
      WHERE current_definition.id = ? AND current_definition.account_id = ?
        AND entry ->> 'code' = jrc_contact_center_ending_action_readinesses.rule_code
    )
  SQL

  def initialize(account:, member:, rule_code:, expected_revision:)
    @account = account
    @context = JrcContactCenter::EndingActions::ConfigurationContext.new(account: account, member: member, for_rule: true)
    @code = rule_code
    @revision = expected_revision
  end

  def call
    @context.call do |member|
      JrcContactCenter::ConfigurationRevision.check_token!(JrcContactCenter::AcwPolicy.new(account: @account).revision, @revision)
      version, rule = current_rule!(member)
      rows = reviewed_definition(version, rule)
      unit = JrcContactCenter::Unit.where(account: @account).find(rule.fetch('scope').fetch('unit_id'))
      applicable = rows.where(source_timezone: unit.timezone).where(MATCHING_VERSIONS, version.revision, version.revision).first
      { last_review: present(rows.first), applicable_review: present(applicable), reviewed_revision: @revision }
    end
  end

  private

  # Return no history of a different private destination or rule definition.
  # Use the same PostgreSQL JSONB digest as the native immutable readiness guard.
  def reviewed_definition(version, rule)
    rows = JrcContactCenter::EndingActionReadiness.where(account: @account, rule_code: rule.fetch('code'))
    rows.where(CURRENT_DEFINITION, version.id, @account.id).order(id: :desc)
  end

  def current_rule!(member)
    JrcContactCenter::EndingActions::Catalogue.new(account: @account).verify_synchronized!
    version = JrcContactCenter::EndingActionVersion.where(account: @account).order(revision: :desc).first!
    document = JrcContactCenter::EndingActions::RuleDefinition.new.call(version.definition)
    rule = document.fetch('entries').find { |entry| entry.fetch('code') == @code }
    raise ActiveRecord::RecordNotFound unless rule

    authorize_legacy_coverage!(member, rule)

    verify_current_binding!(member, rule)

    [version, rule]
  end

  def authorize_legacy_coverage!(member, rule)
    return if rule.fetch('destination_schema_version', 1) == 2

    coverage = JrcContactCenter::CorporateCoverage.new(account: @account, user: member.user)
    raise Pundit::NotAuthorizedError if coverage.configured? && !coverage.group?
  end

  def verify_current_binding!(member, rule)
    input = rule.except('scope').merge('scope_revision' => rule.fetch('scope').fetch('integrity_sha256'))
    checked = JrcContactCenter::EndingActions::RuleInput.new(account: @account, member: member).call(input)
    raise JrcContactCenter::OperationError, 'ending_action_source_scope_changed' unless checked == rule
  end

  def present(receipt)
    return unless receipt

    { id: receipt.id.to_s, version_id: receipt.version_id.to_s, rule_code: receipt.rule_code,
      activated_at: receipt.created_at.iso8601, prospective_only: true }
  end
end

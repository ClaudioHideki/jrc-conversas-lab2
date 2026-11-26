# frozen_string_literal: true

# Internal command, not called by installation or by saving configuration.
# Its future UI/API must explicitly review this exact current native revision.
class JrcContactCenter::EndingActions::ActivateRule
  def initialize(account:, member:, rule_code:, request_key:, expected_revision:)
    @account = account
    @context = JrcContactCenter::EndingActions::ConfigurationContext.new(account: account, member: member, for_rule: true)
    @code = rule_code
    @request_key = request_key
    @expected_revision = expected_revision
  end

  def call
    @context.call do |member|
      JrcContactCenter::ConfigurationRevision.check_token!(JrcContactCenter::AcwPolicy.new(account: @account).revision, @expected_revision)
      validate_request!
      version, rule = current_rule!(member)
      persist!(member, version, rule)
    end
  end

  private

  def current_rule!(member)
    JrcContactCenter::EndingActions::Catalogue.new(account: @account).verify_synchronized!
    version = JrcContactCenter::EndingActionVersion.where(account: @account).order(revision: :desc).first!
    document = JrcContactCenter::EndingActions::RuleDefinition.new.call(version.definition)
    rule = document.fetch('entries').find { |entry| entry.fetch('code') == @code }
    JrcContactCenter::EndingActions::RuleSourceAuthority.new(account: @account, member: member).call(rule) if rule
    ready = rule&.fetch('active') && rule['execution_mode'].present?
    raise JrcContactCenter::OperationError, 'ending_action_not_ready' unless ready

    # Historical v1 activation retains its native whole-account restriction.
    # Only the explicit v2 contract uses the already authorized per-rule scope.
    if rule.fetch('destination_schema_version', 1) != 2
      coverage = JrcContactCenter::CorporateCoverage.new(account: @account, user: member.user)
      raise Pundit::NotAuthorizedError if coverage.configured? && !coverage.group?
    end

    input = rule.except('scope').merge('scope_revision' => rule.fetch('scope').fetch('integrity_sha256'))
    checked = JrcContactCenter::EndingActions::RuleInput.new(account: @account, member: member).call(input)
    raise JrcContactCenter::OperationError, 'ending_action_source_scope_changed' unless checked == rule

    [version, rule]
  end

  def persist!(member, version, rule)
    scope = JrcContactCenter::EndingActionReadiness.where(account: @account)
    previous = scope.find_by(request_key: @request_key)
    return repeated!(previous, member, version, rule) if previous

    scope.create!(version: version, actor_account_user_id: member.id, rule_code: rule.fetch('code'), request_key: @request_key).reload
  end

  def repeated!(previous, member, version, rule)
    unit = JrcContactCenter::Unit.where(account: @account).find(rule.fetch('scope').fetch('unit_id'))
    actual = [previous.version_id, previous.rule_code, previous.source_timezone, previous.actor_account_user_id, previous.actor_user_id]
    same = actual == [version.id, rule.fetch('code'), unit.timezone, member.id, member.user_id]
    raise JrcContactCenter::OperationError.new('ending_activation_request_conflict', status: :conflict) unless same

    previous
  end

  def validate_request!
    valid = @request_key.is_a?(String) && @request_key.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/)
    raise JrcContactCenter::OperationError, 'invalid_ending_activation_request' unless valid
  end
end

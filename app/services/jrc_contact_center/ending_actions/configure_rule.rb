# frozen_string_literal: true

# Existing ACW version writer; current native authority is shared with its scoped editor.
# Reuses native ACW revision/audit and stores only a safe head in Account settings.
class JrcContactCenter::EndingActions::ConfigureRule
  def initialize(account:, member:, input:, expected_revision:)
    @account = account
    @context = JrcContactCenter::EndingActions::ConfigurationContext.new(account: account, member: member, for_rule: true)
    @input = input
    @expected_revision = expected_revision
  end

  def call
    @context.call { |member| update_rule!(member) }
  end

  private

  def update_rule!(member)
    policy = JrcContactCenter::AcwPolicy.new(account: @account)
    JrcContactCenter::ConfigurationRevision.check_token!(policy.revision, @expected_revision)
    catalogue = JrcContactCenter::EndingActions::Catalogue.new(account: @account)
    catalogue.verify_synchronized!
    current = catalogue.call
    rule = validated_rule!(member, current)
    proposed = catalogue.propose(rule: rule)
    persist_definition!(catalogue, proposed) unless proposed == current
    { rule: rule, revision: policy.revision }
  end

  def validated_rule!(member, current)
    rule = JrcContactCenter::EndingActions::RuleInput.new(account: @account, member: member).call(@input)
    JrcContactCenter::EndingActions::RuleSourceAuthority.new(account: @account, member: member).call(rule)
    previous = current.fetch('entries').find { |entry| entry.fetch('code') == rule.fetch('code') }
    authorize_previous!(member, previous) if previous
    rule
  end

  # A caller cannot overwrite an old private destination by replacing it with an
  # accessible project. Unseen unrelated rules remain unchanged server-side.
  def authorize_previous!(member, rule)
    JrcContactCenter::EndingActions::RuleSourceAuthority.new(account: @account, member: member).call(rule)
    rule.fetch('actions').each do |action|
      if rule.fetch('destination_schema_version', 1) == 2
        JrcContactCenter::EndingActions::ConfiguredNativeAction.new(
          account: @account, member: member, source_scope: rule.fetch('scope')
        ).call(action, active: false)
      else
        raise JrcContactCenter::OperationError, 'ending_action_destination_unavailable' unless action.fetch('kind') == 'project_task'

        JrcContactCenter::EndingActions::ProjectTaskParameters.new(member: member).authorize_reference!(action.fetch('parameters'))
      end
    end
  end

  def persist_definition!(catalogue, definition)
    before = JrcContactCenter::AcwPolicyAudit.capture(@account)
    settings = @account.settings.fetch(JrcContactCenter::AcwPolicy::KEY, {}).merge(
      JrcContactCenter::EndingActions::Catalogue::KEY => catalogue.head_for(definition)
    )
    @account.update!(settings: @account.settings.merge(JrcContactCenter::AcwPolicy::KEY => settings))
    after = JrcContactCenter::AcwPolicyAudit.capture(@account)
    audit = JrcContactCenter::AcwPolicyAudit.write!(account: @account, before: before, after: after)
    raise JrcContactCenter::OperationError, 'ending_automation_audit_unavailable' unless audit&.persisted?

    JrcContactCenter::EndingActionVersion.record_change!(account: @account, definition: definition, audit: audit)
    catalogue.verify_synchronized!
  end
end

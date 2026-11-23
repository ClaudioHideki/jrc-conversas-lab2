# frozen_string_literal: true

# Internal writer; no public automation controller exposes it yet.
# Reuses native ACW revision/audit and stores only a safe head in Account settings.
class JrcContactCenter::EndingActions::ConfigureRule
  def initialize(account:, member:, input:, expected_revision:)
    @account = account
    @member_id = member.id
    @user_id = member.user_id
    @input = input
    @expected_revision = expected_revision
  end

  def call
    JrcContactCenter::AuthorityTransaction.call(account: @account, member: nil) do
      member = @account.account_users.find_by!(id: @member_id, user_id: @user_id)
      authorize_configuration!(member)
      Current.set(account: @account, account_user: member, user: member.user, executed_by: nil, contact: nil, inbox: nil) do
        update_rule!(member)
      end
    end
  end

  private

  def authorize_configuration!(member)
    context = { account: @account, account_user: member, user: member.user }
    allowed = member.user.reload.active_for_authentication? && JrcContactCenter::ModulePolicy.new(context, :contact_center).configure?
    coverage = JrcContactCenter::CorporateCoverage.new(account: @account, user: member.user)
    raise Pundit::NotAuthorizedError unless allowed && (!coverage.configured? || coverage.group?)
  end

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
    previous = current.fetch('entries').find { |entry| entry.fetch('code') == rule.fetch('code') }
    authorize_previous!(member, previous) if previous
    rule
  end

  # A caller cannot overwrite an old private destination by replacing it with an
  # accessible project. Unseen unrelated rules remain unchanged server-side.
  def authorize_previous!(member, rule)
    rule.fetch('actions').each do |action|
      raise JrcContactCenter::OperationError, 'ending_action_destination_unavailable' unless action.fetch('kind') == 'project_task'

      JrcContactCenter::EndingActions::ProjectTaskParameters.new(member: member).authorize_reference!(action.fetch('parameters'))
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

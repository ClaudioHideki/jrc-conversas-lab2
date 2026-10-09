# frozen_string_literal: true

class JrcNico::Helpdesk::DeliveryAuthorization
  # The workbook explicitly specifies email only for these alert rules and destinations.
  EVENT_EMAIL_ROLES = {
    'R02' => %w[n2 thiago cs], 'R03' => %w[director thiago], 'R06' => %w[supervisor thiago],
    'R07' => %w[n2 management], 'R08' => %w[director cs], 'R10' => %w[cs thiago], 'R11' => %w[legal thiago ceo]
  }.freeze

  attr_reader :context

  def initialize(source, recipient)
    @source = source
    @recipient = recipient
  end

  def call
    raise Pundit::NotAuthorizedError unless @recipient.account_id == @source.account_id

    @context = JrcNico::Helpdesk::Context.new(@recipient)
    if @source.is_a?(JrcNico::Helpdesk::Event)
      @context.event(@source.id)
    elsif @source.is_a?(JrcNico::Helpdesk::DailyReport)
      JrcNico::Helpdesk::ReportAccess.new(@recipient).authorize!(@source)
    else
      raise ArgumentError, 'Unsupported native delivery source'
    end
    true
  end

  def email!
    call
    allowed = @source.is_a?(JrcNico::Helpdesk::Event) ? event_email_policy? : email_policy?
    raise Pundit::NotAuthorizedError unless allowed

    user = @context.member.user.reload
    raise Pundit::NotAuthorizedError unless user.confirmed_at.present? && user.email.present?

    user.email
  end

  private

  def event_email_policy?
    policy = @source.policy_version.reload
    return false unless policy.published? && policy.enabled? &&
                        policy.digest == JrcNico::Helpdesk::Definition.digest(policy.definition)
    return false unless %w[prepared succeeded].include?(@source.reload.state)

    original = JrcNico::Helpdesk::Context.new(@source.actor)
    original.event(@source.id)
    return false unless policy.eligible?(original.ticket(@source.ticket_id), original.member)

    rule = policy.definition.fetch('rules').fetch(@source.rule_key)
    rule['enabled'] && rule['recipients'].include?(@recipient.id) && rule['channels'].include?('email') && event_email_role?(policy)
  end

  def event_email_role?(policy)
    EVENT_EMAIL_ROLES.fetch(@source.rule_key, []).any? do |role|
      policy.definition.fetch('roles').fetch(role).include?(@recipient.id)
    end
  end

  def email_policy?
    policy = @source.policy_version.reload
    return false unless policy.published? && policy.enabled?

    settings = policy.definition.fetch('daily')
    settings['enabled'] && settings['recipients'].include?(@recipient.id) && settings['channels'].include?('email') &&
      policy.definition.fetch('roles').fetch('thiago').include?(@recipient.id)
  end
end

class JrcNico::Helpdesk::Capture
  TRIGGERS = %w[created closed reopened customer_return monitor].freeze

  def self.call(ticket:, trigger:, origin_key:, member:)
    return [] unless JrcNico::Helpdesk::PolicyVersion.exists?(account_id: ticket.account_id, state: 'published', enabled: true)

    new(member).call(ticket: ticket, trigger: trigger, origin_key: origin_key)
  end

  def initialize(member)
    @context = JrcNico::Helpdesk::Context.new(member)
  end

  def call(ticket:, trigger:, origin_key:)
    raise ArgumentError, 'Invalid capture trigger' unless TRIGGERS.include?(trigger)
    raise ArgumentError, 'A durable source key is required' unless origin_key.is_a?(String) && origin_key.size.between?(1, 120)

    ticket = @context.ticket(ticket.id)
    versions = JrcNico::Helpdesk::PolicyVersion.where(account: @context.account, state: 'published', enabled: true).order(number: :desc)
    policy = versions.find { |version| version.eligible?(ticket, @context.member) }
    return [] unless policy

    facts = JrcNico::Helpdesk::Facts.new(context: @context, policy: policy, ticket: ticket, trigger: trigger).call
    JrcNico::Helpdesk::RuleDetector.new(definition: policy.definition, facts: facts).call.map do |match|
      persist!(policy, ticket, facts, match, origin_key)
    end
  end

  private

  def persist!(policy, ticket, facts, match, origin_key)
    evidence = match.fetch(:evidence).merge('origin_key' => origin_key, 'cycle_key' => facts.fetch('cycle_key'),
                                            'source_occurred_at' => facts.fetch('source_occurred_at'))
    key = correlation(ticket, match.fetch(:rule_key), evidence)
    event = @context.account.with_lock do
      JrcNico::Helpdesk::Event.find_or_create_by!(account: @context.account, correlation_key: key) do |row|
        row.assign_attributes(policy_version: policy, actor: @context.member, ticket: ticket, rule_key: match.fetch(:rule_key),
                              evidence: evidence, detected_at: Time.current)
      end
    end
    JrcNico::Helpdesk::EventJob.perform_later(event.id) if event.state == 'detected'
    event
  end

  def correlation(ticket, key, evidence)
    scope = case key
            when 'R04' then [ticket.unit_id, 'mass', evidence.fetch('ticket_ids').min]
            when 'R02', 'R03' then [ticket.unit_id, ticket.company_id, evidence.fetch('occurrence_ids').min]
            when 'R05', 'R06', 'R07', 'R08', 'R09' then [ticket.id, evidence.fetch('clock_id')]
            when 'R13' then [ticket.id, evidence.fetch('anchor'), evidence.fetch('level')]
            when 'R14' then [ticket.id, evidence.fetch('cycle_key'), evidence.fetch('negative_return_at')]
            when 'R10', 'R11' then [ticket.id, evidence['survey_id'], evidence['evidence_note_ids']]
            else [ticket.id, evidence.fetch('cycle_key')]
            end
    "#{key}:#{JrcNico::Helpdesk::Definition.digest(scope)}"
  end
end

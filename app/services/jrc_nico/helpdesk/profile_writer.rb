# An operator attests classification and source evidence; user messages never set authorization fields.
class JrcNico::Helpdesk::ProfileWriter
  FIELDS = %w[defect_key case_kind customer_note_ids negative_return last_relevant_at].freeze

  def initialize(member)
    @context = JrcNico::Helpdesk::Context.new(member)
  end

  def call(ticket_id:, attributes:)
    values = JrcServiceDesk::Input.attributes(attributes, FIELDS)
    ticket = @context.ticket(ticket_id)
    Pundit.authorize(@context.native.to_h, ticket, :update?)
    ticket.with_lock do
      @context.refresh!
      Pundit.authorize(@context.native.to_h, ticket, :update?)
      profile = JrcNico::Helpdesk::TicketProfile.find_or_initialize_by(account: @context.account, ticket: ticket)
      evidence = evidence_for(profile, ticket, values)
      profile.assign_attributes(values.slice('defect_key', 'case_kind', 'last_relevant_at'))
      profile.assign_attributes(unit: ticket.unit, company_id: ticket.company_id, evidence: evidence)
      profile.save!
      profile
    end
  end

  private

  def evidence_for(profile, ticket, values)
    evidence = profile.evidence.deep_dup
    attest_notes!(evidence, ticket, values['customer_note_ids']) if values.key?('customer_note_ids')
    if values.key?('negative_return')
      JrcNico::Helpdesk::Definition.boolean!(values['negative_return'])
      evidence['negative_return'] = values['negative_return']
      attest_negative!(evidence, ticket, profile) if values['negative_return']
    end
    evidence
  end

  def attest_negative!(evidence, ticket, profile)
    Pundit.authorize(@context.native.to_h, ticket, :view_history?)
    cycle_key = JrcNico::Helpdesk::CycleEvidence.key(ticket)
    return if JrcNico::Helpdesk::CycleEvidence.valid_negative?(ticket: ticket, profile: profile, cycle_key: cycle_key,
                                                               context: @context, now: Time.current)

    evidence.merge!('negative_return_cycle_key' => cycle_key,
                    'negative_return_at' => Time.current.iso8601(6), 'negative_return_attested_by' => @context.member.id)
  end

  def attest_notes!(evidence, ticket, ids)
    JrcNico::Helpdesk::Definition.ids!(ids)
    ids.each { |id| Pundit.authorize(@context.native.to_h, ticket.ticket_notes.find(id), :show?) }
    evidence.merge!('customer_note_ids' => ids, 'attested_by' => @context.member.id, 'attested_at' => Time.current.iso8601(6))
  end
end

require 'rails_helper'

# Real ticket/profile/lifecycle/calendar facts; no detector or Facts replacements.
RSpec.describe JrcNico::Helpdesk::Capture do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures

  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'Synthetic capture company') }
  let(:ticket) { sd_ticket(company_id: company.id, opened_at: selected_rule == 'R13' ? 16.days.ago : Time.current) }
  let(:selected_rule) { 'R10' }
  let(:pilot_companies) { [company.id] }
  let(:definition) do
    value = JrcNico::Helpdesk::Definition.defaults.merge('unit_ids' => [sd_unit.id], 'company_ids' => pilot_companies,
                                                         'operator_ids' => [sd_account_user.id])
    rule = value['rules'][selected_rule]
    rule['enabled'] = true
    rule['confirmed'] = true if rule.key?('confirmed')
    if selected_rule == 'R12'
      rule['critical_company_ids'] = [company.id]
      rule['priority_ids'] = { sd_unit.id.to_s => create(:jrc_sd_priority, unit: sd_unit, position: 2).id }
    end
    value
  end
  let(:policy) do
    JrcNico::Helpdesk::PolicyVersion.create!(account: sd_account, author: sd_account_user, number: 1, state: 'published', enabled: true,
                                             published_at: Time.current, definition: definition,
                                             digest: JrcNico::Helpdesk::Definition.digest(definition))
  end
  let(:writer) { JrcNico::Helpdesk::ProfileWriter.new(sd_account_user) }

  before do
    travel_to Time.iso8601('2026-10-08T12:00:00Z')
    sd_account.update!(custom_attributes: { 'nico_enabled' => true })
    sd_as_admin!
  end

  def profile(row)
    JrcNico::Helpdesk::TicketProfile.create!(account: sd_account, unit: sd_unit, ticket: row, company_id: row.company_id,
                                             case_kind: 'defect', defect_key: 'voice.trunk')
  end

  def capture(row = ticket, origin: 'synthetic-native-source', trigger: nil)
    trigger ||= { 'R14' => 'customer_return', 'R15' => 'closed', 'R16' => 'created' }.fetch(selected_rule, 'monitor')
    JrcNico::Helpdesk::Capture.new(sd_account_user).call(ticket: row, trigger: trigger, origin_key: origin)
  end

  def prepare_occurrences
    counts = { 'R01' => 2, 'R02' => 3, 'R03' => 5, 'R04' => 4 }
    return unless counts.key?(selected_rule)

    (counts.fetch(selected_rule) - 1).times do |index|
      id = if selected_rule == 'R04'
             JrcCustomers::Company.create!(account: sd_account, name: "Synthetic mass customer #{index}").id
           else
             company.id
           end
      pilot_companies << id unless pilot_companies.include?(id)
      profile(sd_ticket(company_id: id))
    end
  end

  def prepare_clock
    return unless %w[R05 R06 R07 R08 R09].include?(selected_rule)

    lc_publish(definition: lc_definition(tracked: true))
    lc_snapshot(ticket)
    lc_execute(ticket, 'work_status')
    clock = ticket.reload.sla_cycles.last.sla_clocks.find_by!(kind: 'resolution')
    travel_to(clock_target(clock), with_usec: true)
  end

  def clock_target(clock)
    return clock.anchor_at + (clock.budget_seconds * 0.8).seconds if selected_rule == 'R05'

    clock.due_at + { 'R06' => 1, 'R07' => 24.hours + 1, 'R08' => 72.hours + 1, 'R09' => 7.days + 1 }.fetch(selected_rule)
  end

  def prepare_text
    return unless %w[R10 R11].include?(selected_rule)

    text = selected_rule == 'R10' ? 'Novamente o mesmo problema; reclamação explícita.' : 'Notificação extrajudicial do advogado.'
    note = JrcServiceDesk::AddNoteService.new(user_context: sd_context).call(ticket_id: ticket.id, attributes: { body: text },
                                                                             idempotency_key: SecureRandom.uuid)
    writer.call(ticket_id: ticket.id, attributes: { customer_note_ids: [note.id] })
  end

  def prepare_closure
    return unless %w[R14 R15].include?(selected_rule)

    lc_publish
    lc_execute(ticket, 'resolve')
    lc_execute(ticket, 'close')
    writer.call(ticket_id: ticket.id, attributes: { negative_return: true }) if selected_rule == 'R14'
  end

  JrcNico::Helpdesk::Definition::RULE_KEYS.each do |key|
    context "with rule #{key}" do
      let(:selected_rule) { key }

      it 'captures real qualifying evidence once and fails closed for foreign tickets and revoked Unit access' do
        profile(ticket)
        prepare_occurrences
        prepare_clock
        prepare_text
        prepare_closure
        policy
        detected = capture
        expect(detected.map(&:rule_key)).to eq([key])
        first = detected.fetch(0)
        expect(first).to be_persisted.and(have_attributes(evidence: include('cycle_key' => JrcNico::Helpdesk::CycleEvidence.key(ticket.reload))))
        expect { expect(capture(origin: 'synthetic-retry-another-source').map(&:id)).to eq([first.id]) }
          .not_to(change(JrcNico::Helpdesk::Event, :count))
        foreign = create(:jrc_sd_ticket, unit: sd_foreign_unit)
        expect { capture(foreign) }.to raise_error(ActiveRecord::RecordNotFound)
        count = JrcNico::Helpdesk::Event.count
        sd_membership.update!(active: false)
        expect { capture }.to raise_error(ActiveRecord::RecordNotFound)
        expect(JrcNico::Helpdesk::Event.count).to eq(count)
      end
    end
  end

  %w[R10 R11].each do |key|
    context "with #{key} text visibility" do
      let(:selected_rule) { key }

      it 'rejects a foreign selected note and ignores a forged stored foreign note selection' do
        policy
        foreign_ticket = create(:jrc_sd_ticket, unit: sd_foreign_unit)
        note = create(:jrc_sd_note, ticket: foreign_ticket, body: 'Reclamação: mesmo problema e notificação extrajudicial do advogado.')
        expect { writer.call(ticket_id: ticket.id, attributes: { customer_note_ids: [note.id] }) }
          .to raise_error(ActiveRecord::RecordNotFound)
        record = profile(ticket)
        record.update!(evidence: { 'customer_note_ids' => [note.id] })
        expect(capture).to be_empty
        expect(JrcNico::Helpdesk::Event.where(account: sd_account)).to be_empty
      end

      it 'revalidates an explicitly attested private technical note after its team grant is revoked' do
        policy
        profile(ticket)
        team = create(:team, account: sd_account)
        grant = create(:team_member, team: team, user: sd_user)
        ticket.update!(team: team)
        text = 'Reclamação: mesmo problema e notificação extrajudicial do advogado. Private financial evidence.'
        note = JrcServiceDesk::AddNoteService.new(user_context: sd_context).call(ticket_id: ticket.id,
                                                                                 attributes: { body: text, visibility: 'technical_team',
                                                                                               audience_team_id: team.id },
                                                                                 idempotency_key: SecureRandom.uuid)
        writer.call(ticket_id: ticket.id, attributes: { customer_note_ids: [note.id] })
        grant.destroy!
        facts = JrcNico::Helpdesk::Facts.new(context: JrcNico::Helpdesk::Context.new(sd_account_user), policy: policy,
                                             ticket: ticket.reload, trigger: 'customer_return').call
        expect(facts).to include('customer_note_ids' => [], 'customer_text' => '')
        expect(capture).to be_empty
        expect { writer.call(ticket_id: ticket.id, attributes: { customer_note_ids: [note.id] }) }.to raise_error(Pundit::NotAuthorizedError)
        expect(JrcNico::Helpdesk::Event.where(account: sd_account)).to be_empty
      end
    end
  end
end

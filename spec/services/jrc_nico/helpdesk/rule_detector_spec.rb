require 'rails_helper'

RSpec.describe JrcNico::Helpdesk::RuleDetector do
  let(:definition) { JrcNico::Helpdesk::Definition.defaults }
  let(:facts) do
    { 'ticket_id' => 1, 'company_id' => 10, 'unit_id' => 20, 'case_kind' => 'defect', 'defect_key' => 'voice.trunk',
      'phase' => 'open', 'open' => true, 'trigger' => 'created', 'cycle_key' => 'service-desk:ticket:1:cycle:initial',
      'service_id' => 30, 'ticket_type_id' => 50, 'priority_id' => 40, 'customer_text' => '', 'customer_note_ids' => [] }
  end

  %w[R01 R02 R03 R04 R05 R06 R07 R08 R09 R10 R11 R12 R13 R14 R15 R16].each do |key|
    it "keeps #{key} OFF unless explicitly configured" do
      expect(described_class.new(definition: definition, facts: facts).call).to be_empty
    end
  end

  [
    ['R01', { 'previous_cases' => [{ 'id' => 2, 'company_id' => 10, 'defect_key' => 'voice.trunk', 'closed_age_seconds' => 14.days }] },
     { 'previous_cases' => [{ 'id' => 2, 'company_id' => 99, 'defect_key' => 'voice.trunk', 'open' => true }] }],
    ['R02', { 'occurrences' => (1..3).map { |id| { 'id' => id, 'company_id' => 10, 'defect_key' => 'voice.trunk', 'age_seconds' => 30.days } } },
     { 'occurrences' => (1..3).map { |id| { 'id' => id, 'company_id' => 10, 'defect_key' => 'different.defect', 'age_seconds' => 0 } } }],
    ['R03', { 'occurrences' => (1..5).map { |id| { 'id' => id, 'company_id' => 10, 'defect_key' => 'voice.trunk', 'age_seconds' => 60.days } } },
     { 'occurrences' => (1..5).map { |id| { 'id' => id, 'company_id' => 10, 'defect_key' => 'voice.trunk', 'age_seconds' => 60.days + 1 } } }],
    ['R04', { 'occurrences' => (1..4).map { |id| { 'id' => id, 'company_id' => id, 'defect_key' => 'voice.trunk', 'age_seconds' => 60.minutes } } },
     { 'occurrences' => (1..10).map { |id| { 'id' => id, 'company_id' => 10, 'defect_key' => 'voice.trunk', 'age_seconds' => 0 } } }],
    ['R05', { 'sla_running' => true, 'sla_elapsed_seconds' => 80, 'sla_budget_seconds' => 100, 'clock_id' => 1, 'due_at' => '2026-10-08T20:00:00Z' },
     { 'sla_running' => true, 'sla_elapsed_seconds' => 100, 'sla_budget_seconds' => 100 }],
    ['R06', { 'sla_running' => true, 'overdue_calendar_seconds' => 1, 'clock_id' => 1, 'due_at' => '2026-10-08T20:00:00Z' },
     { 'sla_running' => true, 'overdue_calendar_seconds' => 0 }],
    ['R07', { 'sla_running' => true, 'overdue_calendar_seconds' => 24.hours + 1, 'clock_id' => 1, 'due_at' => '2026-10-08T20:00:00Z' },
     { 'sla_running' => true, 'overdue_calendar_seconds' => 24.hours }],
    ['R08', { 'sla_running' => true, 'overdue_calendar_seconds' => 72.hours + 1, 'clock_id' => 1, 'due_at' => '2026-10-08T20:00:00Z' },
     { 'sla_running' => true, 'overdue_calendar_seconds' => 72.hours }],
    ['R09', { 'sla_running' => true, 'overdue_calendar_seconds' => 7.days + 1, 'clock_id' => 1, 'due_at' => '2026-10-08T20:00:00Z' },
     { 'sla_running' => true, 'overdue_calendar_seconds' => 7.days }],
    ['R10', { 'customer_text' => 'Novamente o mesmo problema, uma reclamação.' }, { 'customer_text' => 'Problema resolvido, obrigado.' }],
    ['R11', { 'customer_text' => 'Notificação extrajudicial do advogado.' }, { 'customer_text' => 'Reprocesso do registro realizado.' }],
    ['R12', { 'company_id' => 10 }, { 'company_id' => 99 }],
    ['R13', { 'inactive_seconds' => 2.days, 'last_relevant_at' => '2026-10-01T00:00:00Z' }, { 'inactive_seconds' => 2.days - 1 }],
    ['R14', { 'phase' => 'closed', 'negative_return' => true }, { 'phase' => 'open', 'negative_return' => true }],
    ['R15', { 'trigger' => 'closed', 'survey_decision_id' => 50 }, { 'trigger' => 'reopened' }],
    ['R16', { 'service_id' => nil }, { 'service_id' => 30 }]
  ].each do |key, positive, negative|
    context key do
      before do
        definition['rules'][key]['enabled'] = true
        definition['rules'][key]['critical_company_ids'] = [10] if key == 'R12'
      end

      it 'detects the qualifying evidence at its specified boundary' do
        result = described_class.new(definition: definition, facts: facts.merge(positive)).call
        expect(result.pluck(:rule_key)).to eq([key])
        expect(result.first[:evidence]).to be_a(Hash)
      end

      it 'rejects the negative case without creating a decision' do
        expect(described_class.new(definition: definition, facts: facts.merge(negative)).call).to be_empty
      end
    end
  end

  it 'counts distinct ticket occurrences, never retries or messages, for recurrence' do
    definition['rules']['R02']['enabled'] = true
    item = { 'id' => 1, 'company_id' => 10, 'defect_key' => 'voice.trunk', 'age_seconds' => 0 }
    expect(described_class.new(definition: definition, facts: facts.merge('occurrences' => [item] * 30)).call).to be_empty
  end

  it 'requires the same defect and a real canonical Company for R01' do
    definition['rules']['R01']['enabled'] = true
    previous = { 'id' => 2, 'company_id' => 10, 'defect_key' => 'other', 'open' => true }
    expect(described_class.new(definition: definition, facts: facts.merge('previous_cases' => [previous])).call).to be_empty
    expect(described_class.new(definition: definition, facts: facts.merge('company_id' => nil, 'previous_cases' => [previous])).call).to be_empty
  end

  it 'does not apply a calendar threshold to business-hour evidence' do
    definition['rules']['R09'].merge!('enabled' => true, 'basis' => 'business')
    data = facts.merge('sla_running' => true, 'overdue_calendar_seconds' => 8.days, 'overdue_business_seconds' => 24.hours)
    expect(described_class.new(definition: definition, facts: data).call).to be_empty
  end

  it 'does not apply the NPS threshold to native CSAT 1–5' do
    definition['rules']['R10']['enabled'] = true
    data = facts.merge('survey_model' => 'csat', 'survey_scale' => '1-5', 'survey_score' => 1)
    expect(described_class.new(definition: definition, facts: data).call).to be_empty
    data.merge!('survey_model' => 'nps', 'survey_scale' => '0-10', 'survey_score' => 6)
    expect(described_class.new(definition: definition, facts: data).call.pluck(:rule_key)).to eq(['R10'])
    data['survey_score'] = 7
    expect(described_class.new(definition: definition, facts: data).call).to be_empty
  end

  it 'routes the existing native survey recovery without creating another effect' do
    definition['rules']['R10']['enabled'] = true
    result = described_class.new(definition: definition, facts: facts.merge('survey_recovery_id' => 17)).call
    expect(result.first[:evidence]['existing_recovery_id']).to eq(17)
  end

  it 'keeps escalation levels monotonic for inactivity and ignores alerts as activity' do
    definition['rules']['R13']['enabled'] = true
    [2, 5, 15].each_with_index do |days, index|
      result = described_class.new(definition: definition,
                                   facts: facts.merge('inactive_seconds' => days.days,
                                                      'last_relevant_at' => '2026-10-01T00:00:00Z')).call
      expect(result.first[:evidence]['level']).to eq(index + 1)
    end
  end

  it 'never calls the account provider for counting, SLA or rule evaluation' do
    expect(JrcAi::AccountProvider).not_to receive(:resolve)
    described_class.new(definition: definition, facts: facts).call
  end

  it 'does not reopen generic waiting tickets under R14' do
    definition['rules']['R14']['enabled'] = true
    data = facts.merge('phase' => 'waiting', 'negative_return' => true, 'waiting_for_approval' => false)
    expect(described_class.new(definition: definition, facts: data).call).to be_empty
    data['waiting_for_approval'] = true
    expect(described_class.new(definition: definition, facts: data).call.pluck(:rule_key)).to eq(['R14'])
  end

  it 'reports the missing native ticket type without treating a service or text classification as its substitute' do
    definition['rules']['R16']['enabled'] = true
    result = described_class.new(definition: definition, facts: facts.merge('ticket_type_id' => nil)).call
    expect(result).to eq([{ rule_key: 'R16', evidence: { 'missing' => ['ticket_type_id'], 'human_review' => true } }])
  end

  [
    ['R01', { 'previous_cases' => [{ 'id' => 2, 'company_id' => 10, 'defect_key' => 'voice.trunk', 'closed_age_seconds' => 14.days + 1 }] }],
    ['R02', { 'occurrences' => (1..3).map do |id|
      { 'id' => id, 'company_id' => 10, 'defect_key' => 'voice.trunk', 'age_seconds' => 30.days + 1 }
    end }],
    ['R02', { 'occurrences' => (1..2).map { |id| { 'id' => id, 'company_id' => 10, 'defect_key' => 'voice.trunk', 'age_seconds' => 0 } } }],
    ['R03', { 'occurrences' => (1..4).map { |id| { 'id' => id, 'company_id' => 10, 'defect_key' => 'voice.trunk', 'age_seconds' => 0 } } }],
    ['R04', { 'occurrences' => (1..3).map { |id| { 'id' => id, 'company_id' => id, 'defect_key' => 'voice.trunk', 'age_seconds' => 0 } } }],
    ['R04', { 'occurrences' => (1..4).map do |id|
      { 'id' => id, 'company_id' => id, 'defect_key' => 'voice.trunk', 'age_seconds' => 60.minutes + 1 }
    end }],
    ['R05', { 'sla_running' => true, 'sla_elapsed_seconds' => 79.999, 'sla_budget_seconds' => 100 }],
    ['R05', { 'sla_running' => false, 'sla_elapsed_seconds' => 80, 'sla_budget_seconds' => 100 }]
  ].each_with_index do |(key, evidence), index|
    it "rejects the absent #{key} count/time/state boundary #{index + 1}" do
      definition['rules'][key]['enabled'] = true
      expect(described_class.new(definition: definition, facts: facts.merge(evidence)).call).to be_empty
    end
  end

  [[5, 1], [15, 2]].each do |days, level|
    it "keeps R13 at escalation level #{level} one second before #{days} days" do
      definition['rules']['R13']['enabled'] = true
      data = facts.merge('inactive_seconds' => days.days - 1, 'last_relevant_at' => '2026-10-01T00:00:00Z')
      detected = described_class.new(definition: definition, facts: data).call
      expect(detected.first[:evidence]['level']).to eq(level)
    end
  end
end

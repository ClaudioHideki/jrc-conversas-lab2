require 'rails_helper'
require 'stringio'

# Prepared for native CI. Query a real PostgreSQL connection and its actual SQL
# logger; checking filter arrays alone would not prove that binds are redacted.
RSpec.describe JrcContactCenter::EndingActionOrigin, 'and native completion evidence privacy' do
  include_context 'with native ending execution original evidence'

  def capture_execution_evidence_sql
    previous = ActiveRecord::Base.logger
    output = StringIO.new
    ActiveRecord::Base.logger = ActiveSupport::Logger.new(output)
    yield
    output.string
  ensure
    ActiveRecord::Base.logger = previous
  end

  it 'filters the actual origin evidence bind while retaining the account diagnostic' do
    origin
    marker = 'SYNTHETIC_PRIVATE_ORIGIN_BIND_312b'
    log = capture_execution_evidence_sql do
      JrcContactCenter::EndingActionOrigin.uncached do
        JrcContactCenter::EndingActionOrigin.where(account_id: account.id, private_origin_evidence: { source: marker }).load
      end
    end
    expect(log).to include('jrc_contact_center_ending_action_origins', '[FILTERED]', "[\"account_id\", #{account.id}]")
    expect(log).not_to include(marker)
    expect(origin.reload.payload.fetch('actor_user_id')).to eq(actor.id)
  end

  it 'filters the actual completion evidence bind without suppressing ordinary SQL diagnostics' do
    original = origin
    complete_origin_qualification
    marker = 'SYNTHETIC_PRIVATE_COMPLETION_BIND_312b'
    log = capture_execution_evidence_sql do
      JrcContactCenter::EndingActionCompletion.uncached do
        JrcContactCenter::EndingActionCompletion.where(account_id: account.id, private_completion_evidence: { source: marker }).load
      end
    end
    expect(log).to include('jrc_contact_center_ending_action_completions', '[FILTERED]', "[\"account_id\", #{account.id}]")
    expect(log).not_to include(marker)
    expect(JrcContactCenter::EndingActionCompletion.find_by!(origin: original).payload.fetch('reason_code')).to eq('SYNTHETIC_ORIGIN_REASON')
  end

  it 'keeps persisted original and completion payloads out of model inspection' do
    original = origin
    complete_origin_qualification
    completion = JrcContactCenter::EndingActionCompletion.find_by!(origin: original)
    expect(original.inspect).to include('private_origin_evidence: [FILTERED]')
    expect(completion.inspect).to include('private_completion_evidence: [FILTERED]')
    expect(original.inspect).not_to include('captured_call_started_at', 'session_state_at_capture')
    expect(completion.inspect).not_to include('qualification_form_id', 'rule_version_id')
    expect(original.reload.payload.fetch('actor_user_id')).to eq(actor.id)
    expect(completion.reload.payload.fetch('reason_code')).to eq('SYNTHETIC_ORIGIN_REASON')
  end
end

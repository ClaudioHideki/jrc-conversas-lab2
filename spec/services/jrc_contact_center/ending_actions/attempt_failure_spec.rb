require 'rails_helper'

RSpec.describe JrcContactCenter::EndingActions::AttemptFailure do
  it 'retains only an allowed refusal code for a current permission denial' do
    expect(described_class.call(Pundit::NotAuthorizedError.new('SYNTHETIC private project name'))).to eq(%w[blocked authorization_denied])
  end

  it 'does not include a native SQL or integration exception message in failed history' do
    error = ActiveRecord::StatementInvalid.new('SYNTHETIC private SQL, credentials and client content')
    expect(described_class.call(error)).to eq(%w[failed destination_failure])
  end

  it 'records permanent deactivation distinctly without allowing a retry to revive it' do
    error = JrcContactCenter::OperationError.new('ending_action_pending_permanently_blocked')
    expect(described_class.call(error)).to eq(%w[blocked deactivated])
  end

  it 'never persists an unknown operation code or arbitrary message' do
    error = JrcContactCenter::OperationError.new('SYNTHETIC private operation payload')
    expect(described_class.call(error)).to eq(%w[blocked operation_unavailable])
  end

  it 'distinguishes an unconfirmed trigger from an actual completed action' do
    error = JrcContactCenter::OperationError.new('ending_action_trigger_pending')
    expect(described_class.call(error)).to eq(%w[blocked trigger_pending])
  end

  it 'does not turn an agent confirmation requirement into automatic execution' do
    error = JrcContactCenter::OperationError.new('ending_action_requires_agent_confirmation')
    expect(described_class.call(error)).to eq(%w[blocked confirmation_required])
  end

  it 'records a missing currently authorized reference without exporting its identity' do
    expect(described_class.call(ActiveRecord::RecordNotFound.new('SYNTHETIC private reference'))).to eq(%w[blocked reference_unavailable])
  end
end

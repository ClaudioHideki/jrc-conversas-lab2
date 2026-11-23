require 'rails_helper'

RSpec.describe JrcContactCenter::EndingActions::PinnedRule do
  subject(:selection) { described_class.new(account: account, origin: origin) }

  include_context 'with native ending execution original evidence'

  let(:code) { 'SYNTHETIC_ORIGIN_RULE' }
  let(:pinned) { origin.version.definition.fetch('entries').sole }
  let(:input) { pinned.except('scope').merge('scope_revision' => pinned.fetch('scope').fetch('integrity_sha256')) }

  def replace_rule(document)
    revision = JrcContactCenter::AcwPolicy.new(account: account).revision
    JrcContactCenter::EndingActions::ConfigureRule.new(account: account, member: member, input: document, expected_revision: revision).call
  end

  it 'reads the exact original version without arming an effect or granting destination access' do
    expect(selection.call(code)).to eq(pinned)
    expect(selection.call(code)).not_to have_key('execution_token')
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'does not replace the historical destination parameters with a later rule edit' do
    original = pinned.deep_dup
    revised = input.deep_dup
    revised['actions'].sole['parameters']['attributes']['title'] = 'SYNTHETIC later task title'
    replace_rule(revised)
    expect(selection.call(code)).to eq(original)
    expect(selection.call(code).fetch('actions').sole.fetch('parameters').fetch('attributes').fetch('title'))
      .not_to eq('SYNTHETIC later task title')
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'blocks a pending original action after its exact logical rule is disabled' do
    original = origin
    replace_rule(input.merge('active' => false))
    expect { described_class.new(account: account, origin: original).call(code) }
      .to raise_error(JrcContactCenter::OperationError, 'ending_action_pending_permanently_blocked')
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'does not revive an old pending action when a later version reactivates the same logical rule' do
    original = origin
    replace_rule(input.merge('active' => false))
    replace_rule(input.merge('active' => true))
    expect { described_class.new(account: account, origin: original).call(code) }
      .to raise_error(JrcContactCenter::OperationError, 'ending_action_pending_permanently_blocked')
    expect(original.reload.version_id).not_to eq(JrcContactCenter::EndingActionVersion.where(account: account).order(:revision).last.id)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'rejects an unknown logical rule instead of falling back to the latest rule' do
    expect { selection.call('SYNTHETIC_UNKNOWN') }
      .to raise_error(JrcContactCenter::OperationError, 'ending_action_origin_unavailable')
  end

  it 'rejects a foreign account even if the caller knows the immutable origin id' do
    original = origin
    other = create(:account)
    expect { described_class.new(account: other, origin: original).call(code) }.to raise_error(ActiveRecord::RecordNotFound)
  end
end

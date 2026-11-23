require 'rails_helper'

# Actual immutable PostgreSQL history; no call effects, receipts or provider operations are fabricated here.
RSpec.describe JrcContactCenter::EndingActions::BlockingRevision do
  subject(:blocking_revision) { described_class.new(account: account, version_id: origin.id, rule_code: rule_input.fetch('code')).call }

  include_context 'with native ending rule configuration'

  let(:origin) { JrcContactCenter::EndingActionVersion.where(account: account, revision: 1).sole }

  before { configure_native_ending_rule }

  it 'leaves an enabled original rule eligible without changing its exact template or creating an effect' do
    original = origin.attributes.deep_dup
    expect(blocking_revision).to be_nil
    expect(origin.reload.attributes).to eq(original)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'blocks old pending work at the first disabled revision while retaining the immutable original history' do
    original = origin.attributes.deep_dup
    configure_native_ending_rule(rule_input.merge('active' => false))
    expect(blocking_revision).to eq(2)
    expect(origin.reload.attributes).to eq(original)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).order(:revision).pluck(:revision)).to eq([1, 2])
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'does not revive old blocked work after reactivation but permits origins pinned to the new active version' do
    configure_native_ending_rule(rule_input.merge('active' => false))
    configure_native_ending_rule
    expect(blocking_revision).to eq(2)
    latest = JrcContactCenter::EndingActionVersion.where(account: account, revision: 3).sole
    expect(described_class.new(account: account, version_id: latest.id, rule_code: rule_input.fetch('code')).call).to be_nil
    expect(JrcContactCenter::EndingActionVersion.where(account: account).order(:revision).pluck(:revision)).to eq([1, 2, 3])
  end

  it 'keeps the earliest blocking revision across repeated disable and reactivation cycles' do
    2.times do
      configure_native_ending_rule(rule_input.merge('active' => false))
      configure_native_ending_rule
    end
    expect(blocking_revision).to eq(2)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).count).to eq(5)
  end

  it 'does not cancel a different rule when an independently configured rule is disabled' do
    other = rule_input.merge('code' => 'SYNTHETIC_OTHER_RULE')
    configure_native_ending_rule(other)
    configure_native_ending_rule(other.merge('active' => false))
    expect(blocking_revision).to be_nil
    expect(origin.reload.definition.fetch('entries').pluck('code')).to eq(['SYNTHETIC_RULE'])
  end

  it 'does not redirect an original immutable template when an enabled rule is edited' do
    original = origin.definition.deep_dup
    configure_native_ending_rule(rule_input.merge('name' => 'SYNTHETIC revised rule'))
    expect(blocking_revision).to be_nil
    expect(origin.reload.definition).to eq(original)
  end

  it 'rejects a version from another account without treating its identifier as authority' do
    other = create(:account)
    expect { described_class.new(account: other, version_id: origin.id, rule_code: rule_input.fetch('code')).call }
      .to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcContactCenter::EndingActionVersion.where(account: other)).to be_empty
  end

  it 'rejects a missing original rule instead of treating absent data as permission to execute' do
    expect { described_class.new(account: account, version_id: origin.id, rule_code: 'SYNTHETIC_MISSING_RULE').call }
      .to raise_error(JrcContactCenter::OperationError, 'ending_action_origin_unavailable')
  end

  it 'rejects an origin pinned while inactive even after a later reactivation' do
    configure_native_ending_rule(rule_input.merge('active' => false))
    inactive = JrcContactCenter::EndingActionVersion.where(account: account, revision: 2).sole
    configure_native_ending_rule
    expect { described_class.new(account: account, version_id: inactive.id, rule_code: rule_input.fetch('code')).call }
      .to raise_error(JrcContactCenter::OperationError, 'ending_action_origin_unavailable')
  end

  it 'fails closed when the current public head is malformed instead of trusting a cached origin' do
    settings = account.settings.fetch(JrcContactCenter::AcwPolicy::KEY).merge('voice_ending_automations' => false)
    account.settings = account.settings.merge(JrcContactCenter::AcwPolicy::KEY => settings)
    expect { blocking_revision }.to raise_error(JrcContactCenter::OperationError, 'ending_automation_ledger_unavailable')
    expect(account.reload.settings.fetch(JrcContactCenter::AcwPolicy::KEY).fetch('voice_ending_automations')).to be_a(Hash)
  end
end

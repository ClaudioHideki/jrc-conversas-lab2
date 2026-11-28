require 'rails_helper'

RSpec.describe JrcContactCenter::PauseReasonDefinition do
  let(:account) { create(:account) }
  let(:definition) { described_class.new(account: account) }
  let(:legacy) do
    { 'code' => 'synthetic_alert', 'name' => 'SYNTHETIC time notice', 'category' => 'SYNTHETIC', 'description' => '',
      'active' => true, 'minimum_minutes' => nil, 'default_minutes' => 30, 'maximum_minutes' => 60,
      'unit_ids' => [], 'custom_role_ids' => [] }
  end

  it 'retains the exact legacy definition without inserting or disabling its existing time alert' do
    expect(definition.call(legacy)).to eq(legacy)
    expect(definition.call(legacy)).not_to have_key('time_alert_enabled')
    expect(legacy).not_to have_key('time_alert_enabled')
  end

  [true, false].each do |enabled|
    it "preserves an explicitly configured time alert #{enabled.inspect} without changing limits or authority" do
      value = legacy.merge('time_alert_enabled' => enabled)
      expect(definition.call(value)).to eq(value)
      expect(definition.call(value).slice(*described_class::TIMES)).to eq(legacy.slice(*described_class::TIMES))
      expect(definition.call(value).slice('unit_ids', 'custom_role_ids')).to eq(legacy.slice('unit_ids', 'custom_role_ids'))
    end
  end

  [nil, 'true', 'false', 0, 1, [], {}].each do |invalid|
    it "rejects malformed time alert #{invalid.inspect} instead of coercing it into a disabled alert" do
      expect do
        definition.call(legacy.merge('time_alert_enabled' => invalid))
      end.to raise_error(described_class::Invalid) { |failure| expect(failure.fields).to eq(['time_alert_enabled']) }
    end
  end

  it 'changes the catalog revision only on an explicit policy change and never mutates the captured previous value' do
    catalog = JrcContactCenter::PauseCatalog.new(account: account)
    catalog.update!({ 'enforced' => false, 'entries' => [legacy] }, expected_revision: catalog.revision)
    previous = catalog.call.deep_dup
    catalog.update!({ 'enforced' => false, 'entries' => [legacy.merge('time_alert_enabled' => false)] }, expected_revision: catalog.revision)
    expect(catalog.call.fetch('revision')).not_to eq(previous.fetch('revision'))
    expect(catalog.call.fetch('enforced')).to be(false)
    expect(catalog.call.fetch('entries').sole.fetch('time_alert_enabled')).to be(false)
    expect(previous.fetch('entries').sole).to eq(legacy)
    expect(previous.fetch('entries').sole).not_to have_key('time_alert_enabled')
  end
end

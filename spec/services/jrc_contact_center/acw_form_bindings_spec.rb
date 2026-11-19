require 'rails_helper'

RSpec.describe JrcContactCenter::AcwFormBindings do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:definition) do
    { 'fields' => [
      { 'key' => 'feedback', 'label' => 'SYNTHETIC feedback', 'type' => 'text', 'required' => false },
      { 'key' => 'verified', 'label' => 'SYNTHETIC verified', 'type' => 'boolean', 'required' => true }
    ] }
  end
  let(:form) do
    JrcContactCenter::AcwFormTemplate.transaction do
      row = JrcContactCenter::AcwFormTemplate.create!(account: account)
      JrcContactCenter::AcwFormVersion.create!(
        account: account, acw_form_template: row, revision: 1, name: 'SYNTHETIC immutable original', description: '', status: 'active',
        definition: definition, actor_account_user_id: member.id, actor_user_id: actor.id, request_id: SecureRandom.uuid
      )
      row.reload
    end
  end
  let(:rule) { { 'id' => 'synthetic', 'reason_code' => 'order', 'scope' => 'general', 'scope_id' => nil, 'active' => true, 'limit_seconds' => 180 } }
  let(:binding) { { 'rule_id' => 'synthetic', 'form_id' => form.id.to_s, 'revision' => 1, 'required_fields' => ['feedback'] } }
  let(:service) { described_class.new(account: account) }
  let(:pin) { service.validate!([binding], rules: [rule]).sole }

  it 'pins the actual immutable version and unions requirements without changing the native six-field rule or input' do
    previous = [binding.deep_dup, rule.deep_dup]
    expect(pin).to include('form_id' => form.id.to_s, 'revision' => 1, 'integrity_sha256' => form.latest_version.integrity_sha256)
    expect(pin.fetch('required_fields')).to eq(%w[feedback verified])
    expect([binding, rule]).to eq(previous)
    expect(rule.keys.sort).to eq(JrcContactCenter::AcwRulePrecedence::FIELDS.sort)
    expect(JrcContactCenter::AcwFormTemplate.where(account: account).count).to eq(1)
  end

  it 'resolves only the pinned schema and does not expose the catalogue actor or enable attendance access' do
    payload = service.resolve!(pin)
    expect(payload.fetch('name')).to eq('SYNTHETIC immutable original')
    expect(payload.fetch('definition').fetch('fields').map { |field| field.fetch('required') }).to eq([true, true])
    expect(payload.keys).not_to include('actor_user_id', 'actor_account_user_id', 'request_id', 'description')
    expect(form.latest_version.definition).to eq(definition)
    expect(account.settings).not_to have_key('voice_form_bindings')
  end

  [nil, false, {}, 'bindings', Array.new(101) { {} }].each do |value|
    it "rejects malformed binding collection #{value.class}" do
      expect { service.validate!(value, rules: [rule]) }.to raise_error(JrcContactCenter::OperationError, 'invalid_acw_form_bindings')
    end
  end

  it 'rejects duplicate bindings rather than silently replacing the first form' do
    expect { service.validate!([binding, binding], rules: [rule]) }.to raise_error(JrcContactCenter::OperationError, 'invalid_acw_form_bindings')
  end

  it 'rejects an unknown rule instead of adding configuration or deriving authority from the request' do
    expect { service.validate!([binding], rules: []) }.to raise_error(JrcContactCenter::OperationError, 'invalid_acw_form_bindings')
    expect do
      service.validate!([binding.merge('unit_id' => 999)], rules: [rule])
    end.to raise_error(JrcContactCenter::OperationError, 'invalid_acw_form_bindings')
  end

  [nil, false, ['unknown'], ['feedback', 'feedback']].each do |value|
    it "rejects invalid required-field selection #{value.inspect}" do
      expect do
        service.validate!([binding.merge('required_fields' => value)], rules: [rule])
      end.to raise_error(JrcContactCenter::OperationError, 'invalid_acw_form_bindings')
    end
  end

  it 'does not resolve or link a form owned by another account, even with a known ID and checksum' do
    other = described_class.new(account: create(:account))
    expect { other.resolve!(pin) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { other.validate!([binding], rules: [rule]) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'rejects a checksum that does not identify the actual immutable version' do
    expect do
      service.resolve!(pin.merge('integrity_sha256' => '0' * 64))
    end.to raise_error(JrcContactCenter::OperationError, 'invalid_acw_form_bindings')
  end

  it 'keeps the frozen version resolvable after archival while refusing a new binding to that archived catalogue' do
    frozen = pin.deep_dup
    original = form.latest_version
    JrcContactCenter::AcwFormVersion.create!(
      account: account, acw_form_template: form, revision: 2, name: 'SYNTHETIC newer archived', description: '', status: 'archived',
      definition: definition, actor_account_user_id: member.id, actor_user_id: actor.id, request_id: SecureRandom.uuid
    )
    expect(service.resolve!(frozen).fetch('name')).to eq(original.name)
    expect { service.validate!([binding], rules: [rule]) }.to raise_error(JrcContactCenter::OperationError, 'invalid_acw_form_bindings')
    preserved = frozen.slice(*described_class::FIELDS)
    expect(service.validate!([preserved], rules: [rule], preserved: [frozen])).to eq([frozen])
    expect(original.reload.revision).to eq(1)
  end

  [nil, false, 0, '01', '9223372036854775808'].each do |value|
    it "rejects an unsafe form reference #{value.inspect}" do
      expect do
        service.validate!([binding.merge('form_id' => value)], rules: [rule])
      end.to raise_error(JrcContactCenter::OperationError, 'invalid_acw_form_bindings')
    end
  end

  it 'verifies many owned references with one bounded metadata read without loading full definitions on call-end capture' do
    first = pin
    repeated = 100.times.map { |i| first.merge('rule_id' => "synthetic_#{i}") }
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      queries << payload[:sql] if payload[:sql].start_with?('SELECT') && payload[:sql].include?('jrc_contact_center_acw_form_versions')
    end
    begin
      service.verify_metadata!(repeated)
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
    expect(queries.length).to eq(1)
    expect(queries.sole).not_to include('"definition"', 'SELECT "jrc_contact_center_acw_form_versions".*')
  end

  it 'keeps the empty legacy configuration empty and never derives a rule or actor grant' do
    expect(service.references!([], rules: [])).to eq([])
    expect { service.references!([pin], rules: []) }.to raise_error(JrcContactCenter::OperationError, 'invalid_acw_form_bindings')
  end

  it 'validates frozen pins without treating them as a mutable latest-version catalogue' do
    original = pin.deep_dup
    result = service.references!([pin], rules: [rule])
    expect(result).to eq([original])
    result.sole.fetch('required_fields').clear
    result.sole.fetch('integrity_sha256').replace('0' * 64)
    expect(pin).to eq(original)
  end

  [nil, false, 'checksum', 'A' * 64].each do |value|
    it "rejects a malformed frozen checksum #{value.inspect}" do
      expect do
        service.references!([pin.merge('integrity_sha256' => value)], rules: [rule])
      end.to raise_error(JrcContactCenter::OperationError, 'invalid_acw_form_bindings')
    end
  end
end
